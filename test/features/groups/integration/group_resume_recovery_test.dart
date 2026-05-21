import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_missed_message_telemetry.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/application/remove_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_inbox_stores_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart'
    as group_react;
import 'package:flutter_app/features/groups/application/update_group_metadata_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/domain/models/group_backlog_retention_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_history_gap_repair.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_message_receipt.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_repair.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_history_gap_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_audio_recorder_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/fake_upload_wake_lock_driver.dart';
import '../../../shared/fakes/group_test_user.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/helpers/lifecycle_helpers.dart';

const _validContentHash =
    '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a';

String _opaqueReplayCiphertext(String plaintext) =>
    'sealed:${sha256.convert(utf8.encode(plaintext))}';

class _OpaqueReplayBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group.encrypt') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);

      final payload = parsed['payload'] as Map<String, dynamic>;
      final plaintext = payload['plaintext'] as String? ?? '';
      return jsonEncode({
        'ok': true,
        'ciphertext': _opaqueReplayCiphertext(plaintext),
        'nonce': 'ir014-opaque-replay-nonce',
      });
    }

    return super.send(message);
  }
}

/// A bridge that simulates cursor-based inbox retrieval for integration tests.
class _CursorInboxBridge extends FakeBridge {
  final Map<String, _InboxPage> pages = {};

  void addPage(
    String groupId,
    String cursor,
    List<Map<String, dynamic>> messages,
    String nextCursor, {
    List<Map<String, dynamic>> historyGaps = const <Map<String, dynamic>>[],
  }) {
    pages['$groupId:$cursor'] = _InboxPage(messages, nextCursor, historyGaps);
  }

  final Map<String, Map<String, dynamic>> repairResponses = {};

  void addRepairResponse({
    required String groupId,
    required String gapId,
    required String sourcePeerId,
    required Map<String, dynamic> response,
  }) {
    repairResponses['$groupId:$gapId:$sourcePeerId'] = response;
  }

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:inboxRetrieveCursor') {
      if (cmd != null) commandLog.add(cmd);
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;

      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      final cursor = payload['cursor'] as String? ?? '';
      final key = '$groupId:$cursor';

      final page = pages[key];
      if (page != null) {
        return jsonEncode({
          'ok': true,
          'messages': page.messages,
          'cursor': page.nextCursor,
          if (page.historyGaps.isNotEmpty) 'historyGaps': page.historyGaps,
        });
      }
      return jsonEncode({
        'ok': true,
        'messages': <Map<String, dynamic>>[],
        'cursor': '',
      });
    }

    if (cmd == 'group:historyRepairRange') {
      if (cmd != null) commandLog.add(cmd);
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;

      final payload = parsed['payload'] as Map<String, dynamic>;
      final key =
          '${payload['groupId']}:${payload['gapId']}:${payload['sourcePeerId']}';
      final response = repairResponses[key];
      if (response != null) {
        return jsonEncode(response);
      }
      return jsonEncode({
        'ok': false,
        'errorCode': 'GROUP_HISTORY_REPAIR_ERROR',
        'errorMessage': 'missing fake repair response',
      });
    }

    return super.send(message);
  }
}

class _RejoiningCursorInboxBridge extends _CursorInboxBridge {
  _RejoiningCursorInboxBridge({
    required this.network,
    required this.peerId,
    required this.trace,
  }) : super();

  final FakeGroupPubSubNetwork network;
  final String peerId;
  final List<String> trace;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:join') {
      _recordCommand(message, cmd);
      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      trace.add('join:$groupId');
      network.subscribe(groupId, peerId);
      return jsonEncode({'ok': true});
    }

    if (cmd == 'group:inboxRetrieveCursor') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      trace.add('drain:$groupId');
      return super.send(message);
    }

    if (cmd == 'group:acknowledgeRecovery') {
      _recordCommand(message, cmd);
      trace.add('ack');
      return jsonEncode({'ok': true});
    }

    return super.send(message);
  }

  void _recordCommand(String message, String? cmd) {
    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);
    lastCommand = cmd;
    if (cmd != null) {
      commandLog.add(cmd);
    }
  }
}

class _FailFirstCursorInboxBridge extends _CursorInboxBridge {
  final Set<String> failedOnce = {};

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:inboxRetrieveCursor') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      final cursor = payload['cursor'] as String? ?? '';
      final key = '$groupId:$cursor';
      if (failedOnce.add(key)) {
        commandLog.add(cmd!);
        sendCallCount++;
        lastSentMessage = message;
        sentMessages.add(message);
        lastCommand = cmd;
        return jsonEncode({
          'ok': false,
          'errorCode': 'IR008_RETRIEVE_FAILED',
          'errorMessage': 'simulated first cursor retrieve failure',
        });
      }
    }
    return super.send(message);
  }
}

class _InboxPage {
  final List<Map<String, dynamic>> messages;
  final String nextCursor;
  final List<Map<String, dynamic>> historyGaps;
  _InboxPage(this.messages, this.nextCursor, this.historyGaps);
}

class _InMemoryGroupPendingKeyRepairRepository
    implements GroupPendingKeyRepairRepository {
  final Map<String, GroupPendingKeyRepair> repairs = {};

  @override
  Future<GroupPendingKeyRepairUpsertResult> upsertPendingRepair(
    GroupPendingKeyRepair repair,
  ) async {
    final existing = repairs[repair.id];
    if (existing == null) {
      repairs[repair.id] = repair;
      return GroupPendingKeyRepairUpsertResult(repair: repair, created: true);
    }
    final merged = existing.copyWith(updatedAt: repair.updatedAt);
    repairs[repair.id] = merged;
    return GroupPendingKeyRepairUpsertResult(repair: merged, created: false);
  }

  @override
  Future<GroupPendingKeyRepair?> getRepair(String id) async => repairs[id];

  @override
  Future<List<GroupPendingKeyRepair>> getPendingRepairsForGroupEpoch({
    required String groupId,
    required int keyEpoch,
    int limit = 50,
  }) async {
    return repairs.values
        .where(
          (repair) =>
              repair.groupId == groupId &&
              repair.keyEpoch == keyEpoch &&
              repair.status == groupPendingKeyRepairStatusPendingKey,
        )
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<void> recordAttempt(String id, {required String? lastError}) async {
    final existing = repairs[id];
    if (existing == null) return;
    repairs[id] = existing.copyWith(
      attempts: existing.attempts + 1,
      lastError: lastError,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> finalizeRepaired(String id) async {
    final existing = repairs[id];
    if (existing == null || existing.finalizedAt != null) return;
    final now = DateTime.now().toUtc();
    repairs[id] = existing.copyWith(
      status: groupPendingKeyRepairStatusRepaired,
      updatedAt: now,
      finalizedAt: now,
    );
  }

  @override
  Future<void> finalizeUndecryptable(
    String id, {
    required String lastError,
  }) async {
    final existing = repairs[id];
    if (existing == null || existing.finalizedAt != null) return;
    final now = DateTime.now().toUtc();
    repairs[id] = existing.copyWith(
      status: groupPendingKeyRepairStatusUndecryptable,
      lastError: lastError,
      updatedAt: now,
      finalizedAt: now,
    );
  }
}

class _InMemoryGroupHistoryGapRepairRepository
    implements GroupHistoryGapRepairRepository {
  final Map<String, GroupHistoryGapRepair> repairs = {};

  String _key(String groupId, String gapId) => '$groupId:$gapId';

  @override
  Future<GroupHistoryGapRepairUpsertResult> upsertDetected(
    GroupHistoryGapRepair repair,
  ) async {
    final key = _key(repair.groupId, repair.gapId);
    final existing = repairs[key];
    if (existing == null) {
      repairs[key] = repair;
      return GroupHistoryGapRepairUpsertResult(repair: repair, created: true);
    }
    repairs[key] = existing.copyWith(
      candidateSourcePeerIds: repair.candidateSourcePeerIds,
      expectedRangeHash: repair.expectedRangeHash,
      expectedHeadMessageId: repair.expectedHeadMessageId,
      updatedAt: repair.updatedAt,
    );
    return GroupHistoryGapRepairUpsertResult(
      repair: repairs[key]!,
      created: false,
    );
  }

  @override
  Future<GroupHistoryGapRepair?> getRepair({
    required String groupId,
    required String gapId,
  }) async => repairs[_key(groupId, gapId)];

  @override
  Future<GroupHistoryGapRepair?> getLatestRepairForGroup(String groupId) async {
    final groupRepairs = repairs.values
        .where((repair) => repair.groupId == groupId)
        .toList();
    if (groupRepairs.isEmpty) return null;
    groupRepairs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return groupRepairs.first;
  }

  @override
  Future<List<GroupHistoryGapRepair>> getVisibleRepairsForGroup(
    String groupId, {
    int limit = 20,
  }) async {
    return repairs.values
        .where((repair) => repair.groupId == groupId && !repair.isTerminal)
        .take(limit)
        .toList();
  }

  @override
  Future<void> markRepairing({
    required String groupId,
    required String gapId,
  }) async {
    final repair = repairs[_key(groupId, gapId)];
    if (repair == null || repair.isTerminal) return;
    repairs[_key(groupId, gapId)] = repair.copyWith(
      status: groupHistoryGapRepairStatusRepairing,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> recordAttempt({
    required String groupId,
    required String gapId,
    required String sourcePeerId,
    required String? lastError,
  }) async {
    final repair = repairs[_key(groupId, gapId)];
    if (repair == null || repair.isTerminal) return;
    repairs[_key(groupId, gapId)] = repair.copyWith(
      status: groupHistoryGapRepairStatusRepairing,
      attemptedSourcePeerIds: <String>{
        ...repair.attemptedSourcePeerIds,
        sourcePeerId,
      }.toList(),
      failureReason: lastError,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> markRepaired({
    required String groupId,
    required String gapId,
    required List<String> repairedMessageIds,
  }) async {
    final repair = repairs[_key(groupId, gapId)];
    if (repair == null) return;
    final now = DateTime.now().toUtc();
    repairs[_key(groupId, gapId)] = repair.copyWith(
      status: groupHistoryGapRepairStatusRepaired,
      repairedMessageIds: repairedMessageIds,
      failureReason: null,
      updatedAt: now,
      repairedAt: now,
    );
  }

  @override
  Future<void> markFailed({
    required String groupId,
    required String gapId,
    required String reason,
  }) async {
    final repair = repairs[_key(groupId, gapId)];
    if (repair == null ||
        repair.status == groupHistoryGapRepairStatusRepaired) {
      return;
    }
    final now = DateTime.now().toUtc();
    repairs[_key(groupId, gapId)] = repair.copyWith(
      status: groupHistoryGapRepairStatusFailed,
      failureReason: reason,
      updatedAt: now,
      failedAt: now,
    );
  }
}

Future<void> _saveLegacyBacklogSender(
  GroupTestUser user, {
  required String groupId,
  required String peerId,
  required String username,
}) async {
  await user.groupRepo.saveMember(
    GroupMember(
      groupId: groupId,
      peerId: peerId,
      username: username,
      role: MemberRole.writer,
      publicKey: '$peerId-pk',
      mlKemPublicKey: '$peerId-mlkem',
      joinedAt: DateTime.now().toUtc(),
    ),
  );
}

class _Section10TempMediaFileManager extends FakeMediaFileManager {
  _Section10TempMediaFileManager(this.rootDir);

  final Directory rootDir;

  @override
  Future<String> copyToDurableStorage({
    required String sourceFilePath,
    required String messageId,
    required String attachmentId,
    required String mime,
  }) async {
    final extension = p.extension(sourceFilePath);
    final directory = Directory(
      p.join(rootDir.path, 'pending_uploads', messageId),
    );
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    final destination = p.join(directory.path, '$attachmentId$extension');
    await File(sourceFilePath).copy(destination);
    return p.join('pending_uploads', messageId, '$attachmentId$extension');
  }

  @override
  String relativePathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) {
    return p.join('media', contactPeerId, '$blobId${_extensionForMime(mime)}');
  }

  @override
  Future<String> resolveStoredPath(String storedPath) async {
    if (storedPath.startsWith('pending_uploads/') ||
        storedPath.startsWith('pending_uploads\\') ||
        storedPath.startsWith('media/') ||
        storedPath.startsWith('media\\')) {
      return p.join(rootDir.path, storedPath);
    }
    return storedPath;
  }

  @override
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) async {
    final relativePath = relativePathForAttachment(
      contactPeerId: contactPeerId,
      blobId: blobId,
      mime: mime,
    );
    final absolutePath = p.join(rootDir.path, relativePath);
    final file = File(absolutePath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    return absolutePath;
  }
}

Map<String, dynamic> latestBridgePayload(FakeBridge bridge, String command) {
  final raw = bridge.sentMessages.lastWhere(
    (message) =>
        (jsonDecode(message) as Map<String, dynamic>)['cmd'] == command,
    orElse: () => throw StateError('Missing bridge command: $command'),
  );
  return (jsonDecode(raw) as Map<String, dynamic>)['payload']
      as Map<String, dynamic>;
}

List<Map<String, dynamic>> bridgePayloads(FakeBridge bridge, String command) {
  return bridge.sentMessages
      .map((message) => jsonDecode(message) as Map<String, dynamic>)
      .where((message) => message['cmd'] == command)
      .map((message) => message['payload'] as Map<String, dynamic>)
      .toList(growable: false);
}

Map<String, dynamic> _storedGroupReplayEnvelope(String storedMessage) {
  return jsonDecode(storedMessage) as Map<String, dynamic>;
}

Map<String, dynamic> _decodedGroupReplayPayload(String storedMessage) {
  final envelope = _storedGroupReplayEnvelope(storedMessage);
  final ciphertext = envelope['ciphertext'];
  if (envelope['kind'] == 'group_offline_replay' && ciphertext is String) {
    return jsonDecode(ciphertext) as Map<String, dynamic>;
  }
  return envelope;
}

Future<Map<String, dynamic>> _signedReplayRelayMessage({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required Map<String, dynamic> payload,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  String payloadType = groupOfflineReplayPayloadTypeMessage,
  bool includeEnvelopeMessageId = true,
}) async {
  final replayEnvelope = await buildGroupOfflineReplayEnvelope(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: groupId,
    payloadType: payloadType,
    plaintext: jsonEncode(payload),
    messageId: includeEnvelopeMessageId
        ? payload['messageId'] as String?
        : null,
    senderPeerId: senderPeerId,
    senderPublicKey: senderPublicKey,
    senderPrivateKey: senderPrivateKey,
  );
  return {
    'from': senderPeerId,
    'message': replayEnvelope,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };
}

void _addRelayStoredMessagePage({
  required _CursorInboxBridge receiverBridge,
  required String groupId,
  required String fromPeerId,
  required String storedMessage,
  String cursor = '',
  String nextCursor = '',
}) {
  receiverBridge.addPage(groupId, cursor, [
    {
      'from': fromPeerId,
      'message': storedMessage,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    },
  ], nextCursor);
}

void _injectInboxMessageFromLatestStore({
  required FakeBridge senderBridge,
  required _CursorInboxBridge receiverBridge,
  required String receiverPeerId,
  required String groupId,
}) {
  final inboxPayload = latestBridgePayload(senderBridge, 'group:inboxStore');
  final recipients =
      (inboxPayload['recipientPeerIds'] as List<dynamic>? ?? const [])
          .cast<String>();
  expect(recipients, contains(receiverPeerId));
  final storedMessage = inboxPayload['message'] as String;
  final decodedPayload = _decodedGroupReplayPayload(storedMessage);
  var fromPeerId = decodedPayload['senderId'] as String? ?? '';
  if (fromPeerId.isEmpty) {
    try {
      final publishPayload = latestBridgePayload(senderBridge, 'group:publish');
      fromPeerId = publishPayload['senderPeerId'] as String? ?? '';
    } on StateError {
      fromPeerId = '';
    }
  }
  _addRelayStoredMessagePage(
    receiverBridge: receiverBridge,
    groupId: groupId,
    fromPeerId: fromPeerId,
    storedMessage: storedMessage,
  );
}

class _Section10IdentityRepository implements IdentityRepository {
  _Section10IdentityRepository(this.identity);

  final IdentityModel identity;

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {}
}

class _NoOpGroupRepo implements GroupRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoOpMsgRepo implements GroupMessageRepository {
  @override
  Future<int> transitionSendingToFailed() async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGroupMessageListener extends GroupMessageListener {
  _FakeGroupMessageListener(this._stream)
    : super(groupRepo: _NoOpGroupRepo(), msgRepo: _NoOpMsgRepo());

  final Stream<GroupMessage> _stream;

  @override
  Stream<GroupMessage> get groupMessageStream => _stream;
}

class _Section10MirroringBridge extends FakeBridge {
  _Section10MirroringBridge({
    required this.network,
    required this.msgRepo,
    required this.groupRepo,
    List<String>? operationLog,
    this.publishFailuresRemaining = 0,
    this.publishTimeoutsRemaining = 0,
    this.inboxStoreFailuresRemaining = 0,
    this.inboxStoreResponse,
    Map<String, Completer<void>>? commandGates,
  }) : operationLog = operationLog ?? <String>[],
       commandGates = commandGates ?? <String, Completer<void>>{};

  final FakeGroupPubSubNetwork network;
  final InMemoryGroupMessageRepository msgRepo;
  final InMemoryGroupRepository groupRepo;
  final List<String> operationLog;
  int publishFailuresRemaining;
  int publishTimeoutsRemaining;
  int inboxStoreFailuresRemaining;
  final Map<String, dynamic>? inboxStoreResponse;
  final Map<String, Completer<void>> commandGates;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd != null) commandLog.add(cmd);
    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);
    lastCommand = cmd;

    if (cmd != null) {
      operationLog.add('bridge:$cmd');
      final gate = commandGates[cmd];
      if (gate != null) {
        await gate.future;
      }
    }

    switch (cmd) {
      case 'bg:begin':
        return 'section10-bg-task';
      case 'bg:end':
        return '';
      case 'group.encrypt':
        if (!responses.containsKey(cmd)) {
          final payload = parsed['payload'] as Map<String, dynamic>;
          return jsonEncode({
            'ok': true,
            'ciphertext': payload['plaintext'],
            'nonce': 'fake-group-nonce',
          });
        }
        return jsonEncode(responses[cmd]!);
      case 'group.decrypt':
        if (!responses.containsKey(cmd)) {
          final payload = parsed['payload'] as Map<String, dynamic>;
          return jsonEncode({'ok': true, 'plaintext': payload['ciphertext']});
        }
        return jsonEncode(responses[cmd]!);
      case 'payload.sign':
        if (!responses.containsKey(cmd)) {
          return jsonEncode({'ok': true, 'signature': 'fake-signature'});
        }
        return jsonEncode(responses[cmd]!);
      case 'payload.verify':
        if (!responses.containsKey(cmd)) {
          return jsonEncode({'ok': true, 'valid': true});
        }
        return jsonEncode(responses[cmd]!);
      case 'group:publish':
        return _handlePublish(parsed['payload'] as Map<String, dynamic>);
      case 'group:inboxStore':
        if (inboxStoreFailuresRemaining > 0) {
          inboxStoreFailuresRemaining--;
          return jsonEncode({'ok': false, 'errorCode': 'INBOX_STORE_FAILED'});
        }
        return jsonEncode(inboxStoreResponse ?? {'ok': true});
      default:
        if (cmd != null && responses.containsKey(cmd)) {
          return jsonEncode(responses[cmd]!);
        }
        return jsonEncode({'ok': true});
    }
  }

  Future<String> _handlePublish(Map<String, dynamic> payload) async {
    if (publishTimeoutsRemaining > 0) {
      publishTimeoutsRemaining--;
      return jsonEncode({
        'ok': false,
        'errorCode': 'BRIDGE_TIMEOUT',
        'errorMessage': 'publish timed out',
      });
    }

    if (publishFailuresRemaining > 0) {
      publishFailuresRemaining--;
      throw Exception('Simulated publish failure');
    }

    final groupId = payload['groupId'] as String;
    final senderPeerId = payload['senderPeerId'] as String;
    final messageId = payload['messageId'] as String;
    final topicPeers = network
        .getSubscribers(groupId)
        .where((peerId) => peerId != senderPeerId)
        .length;

    if (topicPeers > 0) {
      final savedMessage = await msgRepo.getMessage(messageId);
      final latestKey = await groupRepo.getLatestKey(groupId);
      final envelope = <String, dynamic>{
        'groupId': groupId,
        'senderId': senderPeerId,
        'senderUsername': payload['senderUsername'] as String? ?? '',
        'keyEpoch':
            savedMessage?.keyGeneration ?? latestKey?.keyGeneration ?? 0,
        'text': payload['text'] as String? ?? '',
        'timestamp':
            savedMessage?.timestamp.toUtc().toIso8601String() ??
            DateTime.now().toUtc().toIso8601String(),
        'messageId': messageId,
      };
      if (payload['quotedMessageId'] is String &&
          (payload['quotedMessageId'] as String).isNotEmpty) {
        envelope['quotedMessageId'] = payload['quotedMessageId'];
      }
      if (payload['media'] is List<dynamic>) {
        envelope['media'] = payload['media'] as List<dynamic>;
      }
      await network.publish(groupId, senderPeerId, envelope);
    }

    return jsonEncode({
      'ok': true,
      'messageId': messageId,
      'topicPeers': topicPeers,
    });
  }
}

IdentityModel _identityForUser(GroupTestUser user) {
  final now = DateTime.now().toUtc().toIso8601String();
  return IdentityModel(
    peerId: user.peerId,
    publicKey: user.publicKey,
    privateKey: user.privateKey,
    mnemonic12:
        'one two three four five six seven eight nine ten eleven twelve',
    username: user.username,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pumpFrames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 40,
}) async {
  var pumps = 0;
  while (!condition() && pumps < maxPumps) {
    await tester.pump(const Duration(milliseconds: 50));
    pumps++;
  }
  expect(condition(), isTrue, reason: 'Condition was not met in time');
}

Future<void> _waitUntil(bool Function() condition, {int maxTicks = 100}) async {
  var ticks = 0;
  while (!condition() && ticks < maxTicks) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    ticks++;
  }
  expect(condition(), isTrue, reason: 'Condition was not met in time');
}

int _logIndex(List<String> operationLog, String entry) {
  final index = operationLog.indexOf(entry);
  expect(index, isNot(-1), reason: 'Expected "$entry" in $operationLog');
  return index;
}

void _expectOrdered(List<String> operationLog, String earlier, String later) {
  expect(
    _logIndex(operationLog, earlier),
    lessThan(_logIndex(operationLog, later)),
    reason: 'Expected "$earlier" before "$later" in $operationLog',
  );
}

MediaAttachment _uploadedMedia({
  required String id,
  required String messageId,
  required String mime,
  required String localPath,
  int? width,
  int? height,
  int? durationMs,
  List<double>? waveform,
  String contentHash = _validContentHash,
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: 1,
    mediaType: MediaAttachment.mediaTypeFromMime(mime),
    localPath: localPath,
    downloadStatus: 'done',
    width: width,
    height: height,
    durationMs: durationMs,
    waveform: waveform,
    contentHash: contentHash,
    encryptionKeyBase64: 'key-$id',
    encryptionNonce: 'nonce-$id',
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );
}

String _extensionForMime(String mime) {
  if (mime == 'image/png') return '.png';
  if (mime == 'image/jpeg') return '.jpg';
  if (mime == 'audio/mp4' || mime == 'audio/x-m4a') return '.m4a';
  if (mime == 'audio/mpeg') return '.mp3';
  if (mime == 'video/mp4') return '.mp4';
  return '';
}

Future<void> _sendText(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
  await tester.pump();
}

Future<void> _pumpUntilAsyncCondition(
  WidgetTester tester, {
  required bool Function() condition,
  int maxTicks = 200,
}) async {
  var ticks = 0;
  while (!condition() && ticks < maxTicks) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(const Duration(milliseconds: 50));
    ticks++;
  }
  expect(condition(), isTrue, reason: 'Condition was not met in time');
}

Future<void> _saveKey(
  GroupTestUser user,
  String groupId,
  int keyGeneration,
  String encryptedKey,
) async {
  await user.groupRepo.saveKey(
    GroupKeyInfo(
      groupId: groupId,
      keyGeneration: keyGeneration,
      encryptedKey: encryptedKey,
      createdAt: DateTime.now().toUtc(),
    ),
  );
}

Future<GroupMessage> _latestOutgoingMessage(
  InMemoryGroupMessageRepository repo,
  String groupId, {
  String? text,
}) async {
  final messages = await repo.getMessagesPage(groupId, limit: 100);
  final matches =
      messages
          .where(
            (message) =>
                !message.isIncoming && (text == null || message.text == text),
          )
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  expect(matches, isNotEmpty, reason: 'Missing outgoing message for $groupId');
  return matches.first;
}

Future<void> _pumpSection10SenderWidget(
  WidgetTester tester, {
  required GroupTestUser sender,
  required String groupId,
  required Bridge bridge,
  MediaFileManager? mediaFileManager,
  AudioRecorderService? audioRecorderService,
  UploadMediaFn? uploadMediaFn,
  List<File>? initialAttachments,
}) async {
  final controller = StreamController<GroupMessage>.broadcast();
  addTearDown(() async {
    await controller.close();
  });

  final group = await sender.groupRepo.getGroup(groupId);
  expect(group, isNotNull);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GroupConversationWired(
        group: group!,
        groupRepo: sender.groupRepo,
        msgRepo: sender.msgRepo,
        groupMessageListener: _FakeGroupMessageListener(controller.stream),
        bridge: bridge,
        identityRepo: _Section10IdentityRepository(_identityForUser(sender)),
        contactRepo: InMemoryContactRepository(),
        p2pService: FakeP2PService(),
        mediaAttachmentRepo: sender.mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
        audioRecorderService: audioRecorderService,
        uploadMediaFn: uploadMediaFn ?? uploadMedia,
        initialAttachments: initialAttachments,
      ),
    ),
  );

  await _pumpFrames(tester, count: 10);
}

Future<void> _section10WidgetTextLifecycleProof(
  WidgetTester tester,
  FakeGroupPubSubNetwork network,
) async {
  final admin = GroupTestUser.create(
    peerId: 'admin-widget-text-peer',
    username: 'Alice',
    network: network,
  );
  final reader = GroupTestUser.create(
    peerId: 'reader-widget-text-peer',
    username: 'Bob',
    network: network,
    bridge: _CursorInboxBridge(),
  );
  final onlineReader = GroupTestUser.create(
    peerId: 'online-widget-text-peer',
    username: 'Carol',
    network: network,
  );
  final readerBridge = reader.bridge as _CursorInboxBridge;
  final inboxGate = Completer<void>();
  final senderBridge = _Section10MirroringBridge(
    network: network,
    msgRepo: admin.msgRepo,
    groupRepo: admin.groupRepo,
    operationLog: <String>[],
    commandGates: {'group:inboxStore': inboxGate},
  );

  const groupId = 'group-announce-widget-text';
  await admin.createGroup(
    groupId: groupId,
    name: 'Announcements Widget Text',
    type: GroupType.announcement,
  );
  await admin.addMember(groupId: groupId, invitee: reader);
  await admin.addMember(groupId: groupId, invitee: onlineReader);
  await _saveKey(admin, groupId, 1, 'k1');
  await _saveKey(reader, groupId, 1, 'k1');
  await _saveKey(onlineReader, groupId, 1, 'k1');

  admin.start();
  reader.start();
  onlineReader.start();

  await _pumpSection10SenderWidget(
    tester,
    sender: admin,
    groupId: groupId,
    bridge: senderBridge,
  );

  await simulateBackgroundForegroundCycle(
    bridge: reader.bridge,
    p2pService: FakeP2PService(),
    messageRepo: InMemoryMessageRepository(),
    groupMsgRepo: reader.msgRepo,
    afterPause: () async {
      network.unsubscribe(groupId, reader.peerId);
      await _sendText(tester, 'Announcement via widget');
      await _waitUntil(
        () => senderBridge.commandLog.contains('group:inboxStore'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      _injectInboxMessageFromLatestStore(
        senderBridge: senderBridge,
        receiverBridge: readerBridge,
        receiverPeerId: reader.peerId,
        groupId: groupId,
      );
      inboxGate.complete();
      await _pumpFrames(tester, count: 20);
    },
    afterResume: () async {
      await drainGroupOfflineInbox(
        bridge: reader.bridge,
        groupRepo: reader.groupRepo,
        msgRepo: reader.msgRepo,
      );
      network.subscribe(groupId, reader.peerId);
    },
  );

  final sent = await _latestOutgoingMessage(
    admin.msgRepo,
    groupId,
    text: 'Announcement via widget',
  );
  expect(sent.status, 'sent');
  expect(sent.inboxStored, isTrue);
  expect(senderBridge.commandLog, contains('group:publish'));
  expect(senderBridge.commandLog, contains('group:inboxStore'));
  _expectOrdered(
    senderBridge.operationLog,
    'bridge:bg:begin',
    'bridge:group:publish',
  );
  _expectOrdered(
    senderBridge.operationLog,
    'bridge:group:publish',
    'bridge:group:inboxStore',
  );
  _expectOrdered(
    senderBridge.operationLog,
    'bridge:group:inboxStore',
    'bridge:bg:end',
  );

  final onlineReaderMessages = await onlineReader.loadGroupMessages(groupId);
  expect(onlineReaderMessages.any((message) => message.id == sent.id), isTrue);
  final readerMessages = await reader.loadGroupMessages(groupId);
  expect(readerMessages.any((message) => message.id == sent.id), isTrue);

  admin.dispose();
  reader.dispose();
  onlineReader.dispose();
}

Future<void> _section10WidgetMediaLifecycleProof(
  WidgetTester tester,
  FakeGroupPubSubNetwork network,
) async {
  final admin = GroupTestUser.create(
    peerId: 'admin-widget-media-peer',
    username: 'Alice',
    network: network,
  );
  final reader = GroupTestUser.create(
    peerId: 'reader-widget-media-peer',
    username: 'Bob',
    network: network,
    bridge: _CursorInboxBridge(),
  );
  final onlineReader = GroupTestUser.create(
    peerId: 'online-widget-media-peer',
    username: 'Carol',
    network: network,
  );
  final readerBridge = reader.bridge as _CursorInboxBridge;
  final inboxGate = Completer<void>();
  final senderBridge = _Section10MirroringBridge(
    network: network,
    msgRepo: admin.msgRepo,
    groupRepo: admin.groupRepo,
    operationLog: <String>[],
    commandGates: {'group:inboxStore': inboxGate},
  );
  final tempDir = Directory.systemTemp.createTempSync('section10-media-');
  addTearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });
  final attachment = File(p.join(tempDir.path, 'announcement.jpg'))
    ..writeAsStringSync('image');
  String? uploadedBlobId;

  const groupId = 'group-announce-widget-media';
  await admin.createGroup(
    groupId: groupId,
    name: 'Announcements Widget Media',
    type: GroupType.announcement,
  );
  await admin.addMember(groupId: groupId, invitee: reader);
  await admin.addMember(groupId: groupId, invitee: onlineReader);
  await _saveKey(admin, groupId, 4, 'k4');
  await _saveKey(reader, groupId, 4, 'k4');
  await _saveKey(onlineReader, groupId, 4, 'k4');

  admin.start();
  reader.start();
  onlineReader.start();

  await _pumpSection10SenderWidget(
    tester,
    sender: admin,
    groupId: groupId,
    bridge: senderBridge,
    mediaFileManager: _Section10TempMediaFileManager(tempDir),
    initialAttachments: [attachment],
    uploadMediaFn:
        ({
          required Bridge bridge,
          required String localFilePath,
          required String mime,
          required String recipientPeerId,
          MediaFileManager? mediaFileManager,
          int? width,
          int? height,
          int? durationMs,
          List<double>? waveform,
          List<String>? allowedPeers,
          String? blobId,
        }) async {
          senderBridge.operationLog.add('uploadMediaFn');
          uploadedBlobId = blobId;
          return _uploadedMedia(
            id: 'server-att-widget-media',
            messageId: '',
            mime: mime,
            localPath: localFilePath,
            width: 1080,
            height: 720,
          );
        },
  );

  await simulateBackgroundForegroundCycle(
    bridge: reader.bridge,
    p2pService: FakeP2PService(),
    messageRepo: InMemoryMessageRepository(),
    groupMsgRepo: reader.msgRepo,
    afterPause: () async {
      network.unsubscribe(groupId, reader.peerId);
      await _sendText(tester, 'Photo update');
      await _pumpUntilAsyncCondition(
        tester,
        condition: () => senderBridge.commandLog.contains('group:inboxStore'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      _injectInboxMessageFromLatestStore(
        senderBridge: senderBridge,
        receiverBridge: readerBridge,
        receiverPeerId: reader.peerId,
        groupId: groupId,
      );
      inboxGate.complete();
      await _pumpFrames(tester, count: 20);
    },
    afterResume: () async {
      await drainGroupOfflineInbox(
        bridge: reader.bridge,
        groupRepo: reader.groupRepo,
        msgRepo: reader.msgRepo,
        mediaAttachmentRepo: reader.mediaAttachmentRepo,
      );
      network.subscribe(groupId, reader.peerId);
    },
  );

  final sent = await _latestOutgoingMessage(
    admin.msgRepo,
    groupId,
    text: 'Photo update',
  );
  expect(uploadedBlobId, isNotNull);
  expect(sent.status, 'sent');
  expect(sent.keyGeneration, 4);
  _expectOrdered(senderBridge.operationLog, 'bridge:bg:begin', 'uploadMediaFn');
  _expectOrdered(
    senderBridge.operationLog,
    'uploadMediaFn',
    'bridge:group:publish',
  );
  _expectOrdered(
    senderBridge.operationLog,
    'bridge:group:inboxStore',
    'bridge:bg:end',
  );
  final senderMedia = await admin.mediaAttachmentRepo.getAttachmentsForMessage(
    sent.id,
  );
  expect(senderMedia, hasLength(1));
  expect(senderMedia.single.id, uploadedBlobId);
  expect(senderMedia.single.downloadStatus, 'done');

  final onlineReaderMessages = await onlineReader.loadGroupMessages(groupId);
  final onlineDelivered = onlineReaderMessages.firstWhere(
    (message) => message.id == sent.id,
  );
  expect(onlineDelivered.keyGeneration, 4);
  final onlineReaderMedia = await onlineReader.mediaAttachmentRepo
      .getAttachmentsForMessage(onlineDelivered.id);
  expect(onlineReaderMedia, hasLength(1));
  expect(onlineReaderMedia.single.id, uploadedBlobId);

  final readerMessages = await reader.loadGroupMessages(groupId);
  final readerDelivered = readerMessages.firstWhere(
    (message) => message.id == sent.id,
  );
  expect(readerDelivered.keyGeneration, 4);
  final readerMedia = await reader.mediaAttachmentRepo.getAttachmentsForMessage(
    readerDelivered.id,
  );
  expect(readerMedia, hasLength(1));
  expect(readerMedia.single.id, uploadedBlobId);
  expect(readerMedia.single.width, 1080);
  expect(readerMedia.single.height, 720);

  admin.dispose();
  reader.dispose();
  onlineReader.dispose();
}

Future<void> _section10WidgetVoiceLifecycleProof(
  WidgetTester tester,
  FakeGroupPubSubNetwork network,
) async {
  final admin = GroupTestUser.create(
    peerId: 'admin-widget-voice-peer',
    username: 'Alice',
    network: network,
  );
  final reader = GroupTestUser.create(
    peerId: 'reader-widget-voice-peer',
    username: 'Bob',
    network: network,
    bridge: _CursorInboxBridge(),
  );
  final onlineReader = GroupTestUser.create(
    peerId: 'online-widget-voice-peer',
    username: 'Carol',
    network: network,
  );
  final readerBridge = reader.bridge as _CursorInboxBridge;
  final senderBridge = _Section10MirroringBridge(
    network: network,
    msgRepo: admin.msgRepo,
    groupRepo: admin.groupRepo,
    operationLog: <String>[],
  );
  final mediaFileManager = FakeMediaFileManager();
  final recorder = FakeAudioRecorderService()
    ..fakeDurationMs = 1400
    ..fakeSizeBytes = 36000;
  final tempDir = Directory.systemTemp.createTempSync('section10-voice-');
  addTearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });
  final voiceFile = File(p.join(tempDir.path, 'announcement.m4a'))
    ..writeAsStringSync('voice');
  recorder.fakeOutputPath = voiceFile.path;

  const groupId = 'group-announce-widget-voice';
  await admin.createGroup(
    groupId: groupId,
    name: 'Announcements Widget Voice',
    type: GroupType.announcement,
  );
  await admin.addMember(groupId: groupId, invitee: reader);
  await admin.addMember(groupId: groupId, invitee: onlineReader);
  await _saveKey(admin, groupId, 6, 'k6');
  await _saveKey(reader, groupId, 6, 'k6');
  await _saveKey(onlineReader, groupId, 6, 'k6');

  admin.start();
  reader.start();
  onlineReader.start();

  await _pumpSection10SenderWidget(
    tester,
    sender: admin,
    groupId: groupId,
    bridge: senderBridge,
    mediaFileManager: mediaFileManager,
    audioRecorderService: recorder,
    uploadMediaFn:
        ({
          required Bridge bridge,
          required String localFilePath,
          required String mime,
          required String recipientPeerId,
          MediaFileManager? mediaFileManager,
          int? width,
          int? height,
          int? durationMs,
          List<double>? waveform,
          List<String>? allowedPeers,
          String? blobId,
        }) async {
          senderBridge.operationLog.add('uploadMediaFn');
          return _uploadedMedia(
            id: blobId ?? 'att-widget-voice',
            messageId: '',
            mime: mime,
            localPath: mediaFileManager!.relativePathForAttachment(
              contactPeerId: recipientPeerId,
              blobId: blobId ?? 'att-widget-voice',
              mime: mime,
            ),
            durationMs: durationMs,
            waveform: waveform,
          );
        },
  );

  await simulateBackgroundForegroundCycle(
    bridge: reader.bridge,
    p2pService: FakeP2PService(),
    messageRepo: InMemoryMessageRepository(),
    groupMsgRepo: reader.msgRepo,
    afterPause: () async {
      network.unsubscribe(groupId, reader.peerId);
      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      await (screen.onRecordStart! as Future<void> Function())();
      await _pumpUntil(
        tester,
        () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
      );

      final recordingScreen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      final stopRecording =
          recordingScreen.onRecordStop! as Future<void> Function();
      await tester.runAsync(() async {
        await stopRecording();
      });
      await _waitUntil(
        () => senderBridge.commandLog.contains('group:inboxStore'),
      );
      await _pumpFrames(tester, count: 20);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      _injectInboxMessageFromLatestStore(
        senderBridge: senderBridge,
        receiverBridge: readerBridge,
        receiverPeerId: reader.peerId,
        groupId: groupId,
      );
    },
    afterResume: () async {
      await drainGroupOfflineInbox(
        bridge: reader.bridge,
        groupRepo: reader.groupRepo,
        msgRepo: reader.msgRepo,
        mediaAttachmentRepo: reader.mediaAttachmentRepo,
      );
      network.subscribe(groupId, reader.peerId);
    },
  );

  final sent = await _latestOutgoingMessage(admin.msgRepo, groupId, text: '');
  expect(sent.status, 'sent');
  final inboxPayload = latestBridgePayload(senderBridge, 'group:inboxStore');
  expect(inboxPayload.containsKey('pushTitle'), isFalse);
  expect(inboxPayload.containsKey('pushBody'), isFalse);
  final inboxEnvelope = _decodedGroupReplayPayload(
    inboxPayload['message'] as String,
  );
  expect(inboxEnvelope['text'], isEmpty);
  _expectOrdered(senderBridge.operationLog, 'bridge:bg:begin', 'uploadMediaFn');
  _expectOrdered(
    senderBridge.operationLog,
    'uploadMediaFn',
    'bridge:group:publish',
  );
  _expectOrdered(
    senderBridge.operationLog,
    'bridge:group:inboxStore',
    'bridge:bg:end',
  );

  final onlineReaderMessages = await onlineReader.loadGroupMessages(groupId);
  final onlineDelivered = onlineReaderMessages.firstWhere(
    (message) => message.id == sent.id,
  );
  final onlineReaderMedia = await onlineReader.mediaAttachmentRepo
      .getAttachmentsForMessage(onlineDelivered.id);
  expect(onlineReaderMedia, hasLength(1));
  expect(onlineReaderMedia.single.mediaType, 'audio');

  final readerMessages = await reader.loadGroupMessages(groupId);
  final readerDelivered = readerMessages.firstWhere(
    (message) => message.id == sent.id,
  );
  final readerMedia = await reader.mediaAttachmentRepo.getAttachmentsForMessage(
    readerDelivered.id,
  );
  expect(readerMedia, hasLength(1));
  expect(readerMedia.single.mediaType, 'audio');
  expect(readerMedia.single.durationMs, 1400);

  admin.dispose();
  reader.dispose();
  onlineReader.dispose();
}

Future<void> _section10WidgetRotationLifecycleProof(
  WidgetTester tester,
  FakeGroupPubSubNetwork network,
) async {
  final admin = GroupTestUser.create(
    peerId: 'admin-widget-rotation-peer',
    username: 'Alice',
    network: network,
  );
  final reader = GroupTestUser.create(
    peerId: 'reader-widget-rotation-peer',
    username: 'Bob',
    network: network,
  );
  final senderBridge = _Section10MirroringBridge(
    network: network,
    msgRepo: admin.msgRepo,
    groupRepo: admin.groupRepo,
    operationLog: <String>[],
  );

  const groupId = 'group-announce-widget-rotation';
  await admin.createGroup(
    groupId: groupId,
    name: 'Announcements Widget Rotation',
    type: GroupType.announcement,
  );
  await admin.addMember(groupId: groupId, invitee: reader);
  await _saveKey(admin, groupId, 1, 'k1');
  await _saveKey(reader, groupId, 1, 'k1');

  admin.start();
  reader.start();

  await _saveKey(admin, groupId, 2, 'k2');
  await _saveKey(reader, groupId, 2, 'k2');

  await _pumpSection10SenderWidget(
    tester,
    sender: admin,
    groupId: groupId,
    bridge: senderBridge,
  );

  await _sendText(tester, 'After rotation via widget');
  await _pumpUntil(
    tester,
    () => senderBridge.commandLog.contains('group:inboxStore'),
  );
  await _pumpFrames(tester, count: 20);

  final sent = await _latestOutgoingMessage(
    admin.msgRepo,
    groupId,
    text: 'After rotation via widget',
  );
  expect(sent.status, 'sent');
  expect(sent.keyGeneration, 2);
  final readerMessages = await reader.loadGroupMessages(groupId);
  final delivered = readerMessages.firstWhere(
    (message) => message.id == sent.id,
  );
  expect(delivered.keyGeneration, 2);
  expect(senderBridge.commandLog, contains('group:publish'));
  expect(senderBridge.commandLog, contains('group:inboxStore'));

  admin.dispose();
  reader.dispose();
}

void main() {
  late FakeGroupPubSubNetwork network;

  setUp(() {
    network = FakeGroupPubSubNetwork();
    UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
  });

  tearDown(() {
    UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
  });

  Future<void> pump() => Future.delayed(const Duration(milliseconds: 50));

  Future<void> pumpUntilAsync(
    Future<bool> Function() condition, {
    int maxPumps = 40,
  }) async {
    var pumps = 0;
    while (!(await condition()) && pumps < maxPumps) {
      await pump();
      pumps++;
    }
  }

  group('Group resume recovery integration tests', () {
    test(
      'PREREQ-HISTORY-GAP-REPAIR fake-network repair rejects bad source then restores range before live delivery',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-peer',
          username: 'Admin',
          network: network,
        );
        final reader = GroupTestUser.create(
          peerId: 'reader-peer',
          username: 'Reader',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final source = GroupTestUser.create(
          peerId: 'source-peer',
          username: 'Source',
          network: network,
        );

        const groupId = 'history-gap-group';
        await admin.createGroup(groupId: groupId, name: 'History Gap');
        await admin.addMember(groupId: groupId, invitee: reader);
        await reader.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'history-gap-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );
        await reader.groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: source.peerId,
            username: source.username,
            role: MemberRole.reader,
            publicKey: source.publicKey,
            mlKemPublicKey: 'mlkem-${source.peerId}',
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        final readerBridge = reader.bridge as _CursorInboxBridge;
        final historyRepo = _InMemoryGroupHistoryGapRepairRepository();
        final repairedPayloads = [
          {
            'groupId': groupId,
            'senderId': admin.peerId,
            'senderUsername': admin.username,
            'keyEpoch': 1,
            'text': 'Recovered gap message one',
            'timestamp': DateTime.utc(2026, 5, 1, 12, 1).toIso8601String(),
            'messageId': 'repaired-gap-1',
          },
          {
            'groupId': groupId,
            'senderId': admin.peerId,
            'senderUsername': admin.username,
            'keyEpoch': 1,
            'text': 'Recovered gap message two',
            'timestamp': DateTime.utc(2026, 5, 1, 12, 2).toIso8601String(),
            'messageId': 'repaired-gap-2',
          },
        ];
        final repairedMessages = <Map<String, dynamic>>[];
        for (final payload in repairedPayloads) {
          repairedMessages.add(
            await _signedReplayRelayMessage(
              bridge: reader.bridge,
              groupRepo: reader.groupRepo,
              groupId: groupId,
              payload: payload,
              senderPeerId: admin.peerId,
              senderPublicKey: admin.publicKey,
              senderPrivateKey: admin.privateKey,
            ),
          );
        }
        final rangeHash = computeGroupHistoryRangeHash(repairedMessages);

        readerBridge.addPage(
          groupId,
          '',
          [],
          '',
          historyGaps: [
            {
              'groupId': groupId,
              'gapId': 'gap-1',
              'missingAfterMessageId': 'msg-before',
              'missingBeforeMessageId': 'msg-after',
              'expectedRangeHash': rangeHash,
              'expectedHeadMessageId': 'msg-after',
              'candidateSourcePeerIds': [
                'rogue-peer',
                source.peerId,
                admin.peerId,
              ],
            },
          ],
        );
        readerBridge.addRepairResponse(
          groupId: groupId,
          gapId: 'gap-1',
          sourcePeerId: source.peerId,
          response: {
            'ok': true,
            'groupId': groupId,
            'gapId': 'gap-1',
            'sourcePeerId': source.peerId,
            'rangeHash': 'wrong-hash',
            'headMessageId': 'msg-after',
            'messages': repairedMessages.take(1).toList(),
          },
        );
        readerBridge.addRepairResponse(
          groupId: groupId,
          gapId: 'gap-1',
          sourcePeerId: admin.peerId,
          response: {
            'ok': true,
            'groupId': groupId,
            'gapId': 'gap-1',
            'sourcePeerId': admin.peerId,
            'rangeHash': rangeHash,
            'headMessageId': 'msg-after',
            'messages': repairedMessages,
          },
        );

        await drainGroupOfflineInbox(
          bridge: reader.bridge,
          groupRepo: reader.groupRepo,
          msgRepo: reader.msgRepo,
          historyGapRepairRepo: historyRepo,
        );
        await handleIncomingGroupMessage(
          groupRepo: reader.groupRepo,
          msgRepo: reader.msgRepo,
          groupId: groupId,
          senderId: admin.peerId,
          senderUsername: admin.username,
          keyEpoch: 1,
          text: 'Live after repair',
          timestamp: DateTime.utc(2026, 5, 1, 12, 3).toIso8601String(),
          messageId: 'live-after-repair',
        );

        final repair = await historyRepo.getRepair(
          groupId: groupId,
          gapId: 'gap-1',
        );
        expect(repair!.status, groupHistoryGapRepairStatusRepaired);
        expect(
          repair.attemptedSourcePeerIds,
          containsAll(['rogue-peer', source.peerId, admin.peerId]),
        );
        final messages = await reader.msgRepo.getMessagesPage(groupId);
        expect(messages.map((message) => message.id), [
          'repaired-gap-1',
          'repaired-gap-2',
          'live-after-repair',
        ]);
      },
    );

    test(
      'member backgrounded during send receives missed group messages after resume',
      () async {
        // Arrange: Alice and Bob in a group.
        final alice = GroupTestUser.create(
          peerId: 'alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final bobBridge = bob.bridge as _CursorInboxBridge;

        const groupId = 'group-resume-1';
        await alice.createGroup(groupId: groupId, name: 'Resume Test');
        await alice.addMember(groupId: groupId, invitee: bob);

        await bob.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        alice.start();
        bob.start();

        // Verify normal messaging works.
        await alice.sendGroupMessage(
          groupId: groupId,
          text: 'Before background',
        );
        await pump();
        var bobMessages = await bob.loadGroupMessages(groupId);
        expect(bobMessages.where((m) => m.isIncoming), hasLength(1));

        // Simulate Bob backgrounding: unsubscribe from network.
        network.unsubscribe(groupId, bob.peerId);

        // Alice sends while Bob is backgrounded.
        await alice.sendGroupMessage(
          groupId: groupId,
          text: 'While backgrounded',
        );
        await pump();

        // Bob should NOT have received the message.
        bobMessages = await bob.loadGroupMessages(groupId);
        expect(bobMessages.where((m) => m.isIncoming), hasLength(1));

        // Simulate resume: drain offline inbox (with missed messages).
        final ts = DateTime.now().toUtc().toIso8601String();
        bobBridge.addPage(groupId, '', [
          await _signedReplayRelayMessage(
            bridge: alice.bridge,
            groupRepo: bob.groupRepo,
            groupId: groupId,
            payload: {
              'groupId': groupId,
              'senderId': 'alice-peer',
              'senderUsername': 'Alice',
              'keyEpoch': 0,
              'text': 'While backgrounded',
              'timestamp': ts,
              'messageId': 'msg-missed-1',
            },
            senderPeerId: alice.peerId,
            senderPublicKey: alice.publicKey,
            senderPrivateKey: alice.privateKey,
          ),
        ], '');

        await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
        );

        // Bob should now have 2 incoming messages.
        bobMessages = await bob.loadGroupMessages(groupId);
        expect(bobMessages.where((m) => m.isIncoming), hasLength(2));

        // Re-subscribe Bob.
        network.subscribe(groupId, bob.peerId);

        // New live messages should still work.
        await alice.sendGroupMessage(groupId: groupId, text: 'After resume');
        await pump();
        bobMessages = await bob.loadGroupMessages(groupId);
        expect(bobMessages.where((m) => m.isIncoming), hasLength(3));

        alice.dispose();
        bob.dispose();
      },
    );

    test(
      'PL-001 unicode and multiline text survives live delivery and offline replay',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'pl001-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'pl001-bob-peer',
          username: 'Bob',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final charlie = GroupTestUser.create(
          peerId: 'pl001-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-pl001-unicode-multiline';
        const messageId = 'pl001-live-replay-unicode';
        const pl001Text =
            'PL-001 emoji 👩‍💻🚀\n'
            'RTL مرحبا שלום 123\n'
            'Combining cafe\u0301 na\u0308ive\n'
            'Tabs\tand symbols ✓';
        final baseTime = DateTime.now().toUtc();
        final createdAt = baseTime.subtract(const Duration(seconds: 2));
        final joinedAt = baseTime.subtract(const Duration(seconds: 1));
        final sentAt = baseTime.add(const Duration(seconds: 1));

        await alice.createGroup(
          groupId: groupId,
          name: 'PL-001 Group',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: joinedAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: joinedAt,
        );
        await _saveKey(alice, groupId, 1, 'pl001-k1');
        await _saveKey(bob, groupId, 1, 'pl001-k1');
        await _saveKey(charlie, groupId, 1, 'pl001-k1');

        alice.start();
        charlie.start();

        final (sendResult, sentMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: pl001Text,
          messageId: messageId,
          timestamp: sentAt,
        );
        expect(sendResult, SendGroupMessageResult.success);
        expect(sentMessage, isNotNull);
        expect(sentMessage!.text, pl001Text);

        await pumpUntilAsync(
          () async => (await charlie.msgRepo.getMessage(messageId)) != null,
        );
        final charlieRows = (await charlie.loadGroupMessages(
          groupId,
        )).where((message) => message.id == messageId).toList();
        expect(charlieRows, hasLength(1));
        expect(charlieRows.single.text, pl001Text);
        expect(charlieRows.single.isIncoming, isTrue);
        expect(charlieRows.single.keyGeneration, 1);

        expect(await bob.msgRepo.getMessage(messageId), isNull);

        final storedReplay =
            latestBridgePayload(alice.bridge, 'group:inboxStore')['message']
                as String;
        final replayPayload = _decodedGroupReplayPayload(storedReplay);
        expect(replayPayload['messageId'], messageId);
        expect(replayPayload['keyEpoch'], 1);
        expect(replayPayload['text'], pl001Text);

        final bobBridge = bob.bridge as _CursorInboxBridge;
        bobBridge.addPage(groupId, '', [
          {
            'from': alice.peerId,
            'message': storedReplay,
            'timestamp': sentAt.millisecondsSinceEpoch,
          },
        ], 'cursor-pl001');

        bob.start();
        await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          groupMessageListener: bob.groupMessageListener,
          mediaAttachmentRepo: bob.mediaAttachmentRepo,
          selfPeerId: bob.peerId,
          drainAllPages: false,
        );
        await pumpUntilAsync(
          () async => (await bob.msgRepo.getMessage(messageId)) != null,
        );

        final bobRows = (await bob.loadGroupMessages(
          groupId,
        )).where((message) => message.id == messageId).toList();
        expect(bobRows, hasLength(1));
        expect(bobRows.single.text, pl001Text);
        expect(bobRows.single.senderPeerId, alice.peerId);
        expect(bobRows.single.isIncoming, isTrue);
        expect(bobRows.single.keyGeneration, 1);
        expect(await bob.msgRepo.getInboxCursor(groupId), 'cursor-pl001');
      },
    );

    test(
      'PL-004 quote ids survive live replay and re-add visibility boundaries',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'pl004-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'pl004-bob-peer',
          username: 'Bob',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final charlie = GroupTestUser.create(
          peerId: 'pl004-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-pl004-quotes';
        const parentId = 'pl004-parent-before-replay';
        const quoteId = 'pl004-quote-before-replay';
        const removedWindowQuoteId = 'pl004-removed-window-quote';
        const postReaddParentId = 'pl004-post-readd-parent';
        const postReaddQuoteId = 'pl004-post-readd-quote';
        final createdAt = DateTime.utc(2026, 5, 13, 20, 50);
        final groupCreatedAt = createdAt.subtract(const Duration(seconds: 2));
        final joinedAt = createdAt.subtract(const Duration(seconds: 1));

        await alice.createGroup(
          groupId: groupId,
          name: 'PL-004 Quotes',
          createdAt: groupCreatedAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: joinedAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: joinedAt,
        );
        await _saveKey(alice, groupId, 1, 'pl004-k1');
        await _saveKey(bob, groupId, 1, 'pl004-k1');
        await _saveKey(charlie, groupId, 1, 'pl004-k1');

        alice.start();
        charlie.start();
        network.unsubscribe(groupId, bob.peerId);

        final (parentResult, parent) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'PL-004 visible parent before replay',
          messageId: parentId,
          timestamp: createdAt,
        );
        expect(parentResult, SendGroupMessageResult.success);
        expect(parent, isNotNull);

        final (quoteResult, quote) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'PL-004 quoted reply before replay',
          quotedMessageId: parent!.id,
          messageId: quoteId,
          timestamp: createdAt.add(const Duration(seconds: 1)),
        );
        expect(quoteResult, SendGroupMessageResult.success);
        expect(quote, isNotNull);

        await pumpUntilAsync(() async {
          final charlieMessages = await charlie.loadGroupMessages(groupId);
          return charlieMessages.any((message) => message.id == quoteId);
        }, maxPumps: 120);
        final charlieInitial = await charlie.loadGroupMessages(groupId);
        expect(
          charlieInitial.where((message) => message.id == parentId),
          hasLength(1),
        );
        final charlieInitialQuote = charlieInitial.singleWhere(
          (message) => message.id == quoteId,
        );
        expect(charlieInitialQuote.quotedMessageId, parentId);
        expect(await bob.loadGroupMessages(groupId), isEmpty);

        String storedReplayFor(String messageId) {
          return bridgePayloads(alice.bridge, 'group:inboxStore').singleWhere((
                payload,
              ) {
                final replayPayload = _decodedGroupReplayPayload(
                  payload['message'] as String,
                );
                return replayPayload['messageId'] == messageId;
              })['message']
              as String;
        }

        final parentReplay = storedReplayFor(parentId);
        final quoteReplay = storedReplayFor(quoteId);
        expect(
          _decodedGroupReplayPayload(quoteReplay)['quotedMessageId'],
          parentId,
        );

        final bobBridge = bob.bridge as _CursorInboxBridge;
        bobBridge.addPage(groupId, '', [
          {
            'from': alice.peerId,
            'message': parentReplay,
            'timestamp': createdAt.millisecondsSinceEpoch,
          },
          {
            'from': alice.peerId,
            'message': quoteReplay,
            'timestamp': createdAt
                .add(const Duration(seconds: 1))
                .millisecondsSinceEpoch,
          },
        ], 'cursor-pl004');

        bob.start();
        await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          groupMessageListener: bob.groupMessageListener,
          mediaAttachmentRepo: bob.mediaAttachmentRepo,
          selfPeerId: bob.peerId,
          drainAllPages: false,
        );
        await pumpUntilAsync(() async {
          final bobMessages = await bob.loadGroupMessages(groupId);
          return bobMessages.any((message) => message.id == quoteId);
        }, maxPumps: 120);
        final bobReplay = await bob.loadGroupMessages(groupId);
        expect(
          bobReplay.where((message) => message.id == parentId),
          hasLength(1),
        );
        final bobReplayQuote = bobReplay.singleWhere(
          (message) => message.id == quoteId,
        );
        expect(bobReplayQuote.quotedMessageId, parentId);
        expect(await bob.msgRepo.getInboxCursor(groupId), 'cursor-pl004');

        network.subscribe(groupId, bob.peerId);
        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await pump();
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

        final (removedQuoteResult, removedQuote) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'PL-004 quoted reply while Charlie is removed',
              quotedMessageId: parentId,
              messageId: removedWindowQuoteId,
              timestamp: createdAt.add(const Duration(minutes: 1, seconds: 1)),
            );
        expect(removedQuoteResult, SendGroupMessageResult.success);
        expect(removedQuote, isNotNull);
        await pumpUntilAsync(() async {
          final bobMessages = await bob.loadGroupMessages(groupId);
          return bobMessages.any(
            (message) => message.id == removedWindowQuoteId,
          );
        }, maxPumps: 120);
        expect(
          (await bob.loadGroupMessages(groupId))
              .singleWhere((message) => message.id == removedWindowQuoteId)
              .quotedMessageId,
          parentId,
        );
        expect(
          (await charlie.loadGroupMessages(
            groupId,
          )).where((message) => message.id == removedWindowQuoteId),
          isEmpty,
        );

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 2)),
        );
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: createdAt.add(const Duration(minutes: 2)),
        );
        await pump();
        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);

        final (postParentResult, postParent) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'PL-004 visible parent after re-add',
              messageId: postReaddParentId,
              timestamp: createdAt.add(const Duration(minutes: 2, seconds: 1)),
            );
        expect(postParentResult, SendGroupMessageResult.success);
        expect(postParent, isNotNull);
        final (postQuoteResult, postQuote) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'PL-004 quoted reply after re-add',
              quotedMessageId: postParent!.id,
              messageId: postReaddQuoteId,
              timestamp: createdAt.add(const Duration(minutes: 2, seconds: 2)),
            );
        expect(postQuoteResult, SendGroupMessageResult.success);
        expect(postQuote, isNotNull);

        Future<void> expectPostReaddQuote(GroupTestUser user) async {
          await pumpUntilAsync(() async {
            final messages = await user.loadGroupMessages(groupId);
            return messages.any((message) => message.id == postReaddQuoteId);
          }, maxPumps: 120);
          final messages = await user.loadGroupMessages(groupId);
          expect(
            messages.where((message) => message.id == postReaddParentId),
            hasLength(1),
            reason: '${user.username} must have the visible post-readd parent',
          );
          final quoteRow = messages.singleWhere(
            (message) => message.id == postReaddQuoteId,
          );
          expect(quoteRow.quotedMessageId, postReaddParentId);
        }

        await expectPostReaddQuote(bob);
        await expectPostReaddQuote(charlie);
      },
    );

    test(
      'GP-026 same message is not duplicated if both pubsub and group inbox deliver it',
      () async {
        final bob = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final bobBridge = bob.bridge as _CursorInboxBridge;

        const groupId = 'group-dedup-1';
        const sharedMessageId = 'msg-dedup-shared';
        final ts = DateTime.now().toUtc();

        // Set up Bob's group.
        await bob.groupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Dedup Test',
            type: GroupType.chat,
            topicName: 'topic-$groupId',
            createdAt: ts,
            createdBy: 'alice-peer',
            myRole: GroupRole.member,
          ),
        );
        await bob.groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'alice-peer',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: ts,
          ),
        );
        await bob.groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'bob-peer',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob',
            joinedAt: ts,
          ),
        );
        await bob.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-key',
            createdAt: ts,
          ),
        );

        bob.start();
        network.subscribe(groupId, bob.peerId);

        // Simulate pubsub delivery with a known messageId.
        final pubsubController = network.registerPeer('alice-pubsub-sim');
        network.subscribe(groupId, 'alice-pubsub-sim');

        // Deliver via pubsub (simulate what the listener receives).
        await handleIncomingGroupMessage(
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          groupId: groupId,
          senderId: 'alice-peer',
          senderUsername: 'Alice',
          keyEpoch: 0,
          text: 'Dedup test msg',
          timestamp: ts.toIso8601String(),
          messageId: sharedMessageId,
        );

        var bobMessages = await bob.loadGroupMessages(groupId);
        expect(bobMessages.where((m) => m.isIncoming).length, 1);

        // Now drain inbox which also has the same message with the same messageId.
        bobBridge.addPage(groupId, '', [
          await _signedReplayRelayMessage(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            groupId: groupId,
            payload: {
              'groupId': groupId,
              'senderId': 'alice-peer',
              'senderUsername': 'Alice',
              'keyEpoch': 0,
              'text': 'Tampered inbox copy',
              'timestamp': ts.toIso8601String(),
              'messageId': sharedMessageId,
            },
            senderPeerId: 'alice-peer',
            senderPublicKey: 'pk-alice',
            senderPrivateKey: 'sk-alice',
          ),
        ], '');

        await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
        );

        // Still only 1 incoming message — deduplicated by messageId.
        bobMessages = await bob.loadGroupMessages(groupId);
        expect(
          bobMessages.where((m) => m.isIncoming).length,
          1,
          reason: 'Message should not be duplicated by inbox drain',
        );
        expect(
          bobMessages.singleWhere((m) => m.id == sharedMessageId).text,
          'Dedup test msg',
          reason: 'Conflicting replay content must not overwrite live content',
        );

        pubsubController.close();
        bob.dispose();
      },
    );

    test(
      'IR-011 fake-network history repair validates request identity and source peer before mutation',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'ir011-admin-peer',
          username: 'Admin',
          network: network,
        );
        final reader = GroupTestUser.create(
          peerId: 'ir011-reader-peer',
          username: 'Reader',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final groupMismatchSource = GroupTestUser.create(
          peerId: 'ir011-group-mismatch-peer',
          username: 'Group Mismatch',
          network: network,
        );
        final gapMismatchSource = GroupTestUser.create(
          peerId: 'ir011-gap-mismatch-peer',
          username: 'Gap Mismatch',
          network: network,
        );
        final sourceMismatchSource = GroupTestUser.create(
          peerId: 'ir011-source-mismatch-peer',
          username: 'Source Mismatch',
          network: network,
        );
        final fallbackSource = GroupTestUser.create(
          peerId: 'ir011-fallback-peer',
          username: 'Fallback',
          network: network,
        );

        const groupId = 'ir011-history-gap-group';
        await admin.createGroup(groupId: groupId, name: 'IR011 History Gap');
        await admin.addMember(groupId: groupId, invitee: reader);
        await reader.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'ir011-history-gap-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );
        for (final repairSource in [
          groupMismatchSource,
          gapMismatchSource,
          sourceMismatchSource,
          fallbackSource,
        ]) {
          await reader.groupRepo.saveMember(
            GroupMember(
              groupId: groupId,
              peerId: repairSource.peerId,
              username: repairSource.username,
              role: MemberRole.reader,
              publicKey: repairSource.publicKey,
              mlKemPublicKey: 'mlkem-${repairSource.peerId}',
              joinedAt: DateTime.now().toUtc(),
            ),
          );
        }

        final readerBridge = reader.bridge as _CursorInboxBridge;
        final historyRepo = _InMemoryGroupHistoryGapRepairRepository();
        final repairBaseTime = DateTime.now().toUtc().add(
          const Duration(minutes: 1),
        );

        Future<Map<String, dynamic>> repairMessage({
          required String id,
          required String text,
          required DateTime timestamp,
        }) {
          return _signedReplayRelayMessage(
            bridge: reader.bridge,
            groupRepo: reader.groupRepo,
            groupId: groupId,
            payload: {
              'groupId': groupId,
              'senderId': admin.peerId,
              'senderUsername': admin.username,
              'keyEpoch': 1,
              'text': text,
              'timestamp': timestamp.toIso8601String(),
              'messageId': id,
            },
            senderPeerId: admin.peerId,
            senderPublicKey: admin.publicKey,
            senderPrivateKey: admin.privateKey,
          );
        }

        final rejectedGroupMessages = [
          await repairMessage(
            id: 'ir011-fake-rejected-group',
            text: 'wrong group repair must not apply',
            timestamp: repairBaseTime,
          ),
        ];
        final rejectedGapMessages = [
          await repairMessage(
            id: 'ir011-fake-rejected-gap',
            text: 'wrong gap repair must not apply',
            timestamp: repairBaseTime.add(const Duration(seconds: 1)),
          ),
        ];
        final rejectedSourceMessages = [
          await repairMessage(
            id: 'ir011-fake-rejected-source',
            text: 'wrong source repair must not apply',
            timestamp: repairBaseTime.add(const Duration(seconds: 2)),
          ),
        ];
        final validMessages = [
          await repairMessage(
            id: 'ir011-fake-valid-fallback',
            text: 'valid fallback repair applies',
            timestamp: repairBaseTime.add(const Duration(seconds: 3)),
          ),
        ];
        final rangeHash = computeGroupHistoryRangeHash(validMessages);

        readerBridge.addPage(
          groupId,
          '',
          [],
          '',
          historyGaps: [
            {
              'groupId': 'wrong-group',
              'gapId': 'ir011-wrong-group-gap',
              'missingAfterMessageId': 'msg-before',
              'missingBeforeMessageId': 'msg-after',
              'expectedRangeHash': rangeHash,
              'expectedHeadMessageId': 'msg-after',
              'candidateSourcePeerIds': [fallbackSource.peerId],
            },
            {
              'groupId': groupId,
              'gapId': 'ir011-gap-valid',
              'missingAfterMessageId': 'msg-before',
              'missingBeforeMessageId': 'msg-after',
              'expectedRangeHash': rangeHash,
              'expectedHeadMessageId': 'msg-after',
              'candidateSourcePeerIds': [
                'ir011-rogue-peer',
                groupMismatchSource.peerId,
                gapMismatchSource.peerId,
                sourceMismatchSource.peerId,
                fallbackSource.peerId,
              ],
            },
          ],
        );
        readerBridge.addRepairResponse(
          groupId: groupId,
          gapId: 'ir011-gap-valid',
          sourcePeerId: groupMismatchSource.peerId,
          response: {
            'ok': true,
            'groupId': 'wrong-group',
            'gapId': 'ir011-gap-valid',
            'sourcePeerId': groupMismatchSource.peerId,
            'rangeHash': rangeHash,
            'headMessageId': 'msg-after',
            'messages': rejectedGroupMessages,
          },
        );
        readerBridge.addRepairResponse(
          groupId: groupId,
          gapId: 'ir011-gap-valid',
          sourcePeerId: gapMismatchSource.peerId,
          response: {
            'ok': true,
            'groupId': groupId,
            'gapId': 'wrong-gap',
            'sourcePeerId': gapMismatchSource.peerId,
            'rangeHash': rangeHash,
            'headMessageId': 'msg-after',
            'messages': rejectedGapMessages,
          },
        );
        readerBridge.addRepairResponse(
          groupId: groupId,
          gapId: 'ir011-gap-valid',
          sourcePeerId: sourceMismatchSource.peerId,
          response: {
            'ok': true,
            'groupId': groupId,
            'gapId': 'ir011-gap-valid',
            'sourcePeerId': 'ir011-other-source-peer',
            'rangeHash': rangeHash,
            'headMessageId': 'msg-after',
            'messages': rejectedSourceMessages,
          },
        );
        readerBridge.addRepairResponse(
          groupId: groupId,
          gapId: 'ir011-gap-valid',
          sourcePeerId: fallbackSource.peerId,
          response: {
            'ok': true,
            'groupId': groupId,
            'gapId': 'ir011-gap-valid',
            'sourcePeerId': fallbackSource.peerId,
            'rangeHash': rangeHash,
            'headMessageId': 'msg-after',
            'messages': validMessages,
          },
        );

        await drainGroupOfflineInbox(
          bridge: reader.bridge,
          groupRepo: reader.groupRepo,
          msgRepo: reader.msgRepo,
          historyGapRepairRepo: historyRepo,
        );

        expect(
          await historyRepo.getRepair(
            groupId: 'wrong-group',
            gapId: 'ir011-wrong-group-gap',
          ),
          isNull,
        );
        final repair = await historyRepo.getRepair(
          groupId: groupId,
          gapId: 'ir011-gap-valid',
        );
        expect(repair!.status, groupHistoryGapRepairStatusRepaired);
        expect(
          repair.attemptedSourcePeerIds,
          containsAll([
            'ir011-rogue-peer',
            groupMismatchSource.peerId,
            gapMismatchSource.peerId,
            sourceMismatchSource.peerId,
            fallbackSource.peerId,
          ]),
        );
        expect(repair.repairedMessageIds, ['ir011-fake-valid-fallback']);
        expect(repair.failureReason, isNull);

        final repairRequests = bridgePayloads(
          reader.bridge,
          'group:historyRepairRange',
        );
        expect(
          repairRequests.map((payload) => payload['sourcePeerId']).toList(),
          [
            groupMismatchSource.peerId,
            gapMismatchSource.peerId,
            sourceMismatchSource.peerId,
            fallbackSource.peerId,
          ],
        );
        expect(
          repairRequests.map((payload) => payload['sourcePeerId']),
          isNot(contains('ir011-rogue-peer')),
        );
        expect(repairRequests.map((payload) => payload['groupId']).toSet(), {
          groupId,
        });
        expect(repairRequests.map((payload) => payload['gapId']).toSet(), {
          'ir011-gap-valid',
        });

        final messages = await reader.msgRepo.getMessagesPage(groupId);
        expect(messages.map((message) => message.id), [
          'ir011-fake-valid-fallback',
        ]);
      },
    );

    test(
      'IR-012 fake-network repair rejects wrong hash and head then restores range before live delivery',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-peer',
          username: 'Admin',
          network: network,
        );
        final reader = GroupTestUser.create(
          peerId: 'reader-peer',
          username: 'Reader',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final source = GroupTestUser.create(
          peerId: 'source-peer',
          username: 'Source',
          network: network,
        );
        final headSource = GroupTestUser.create(
          peerId: 'head-source-peer',
          username: 'Head Source',
          network: network,
        );

        const groupId = 'history-gap-group';
        await admin.createGroup(groupId: groupId, name: 'History Gap');
        await admin.addMember(groupId: groupId, invitee: reader);
        await reader.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'history-gap-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );
        for (final repairSource in [source, headSource]) {
          await reader.groupRepo.saveMember(
            GroupMember(
              groupId: groupId,
              peerId: repairSource.peerId,
              username: repairSource.username,
              role: MemberRole.reader,
              publicKey: repairSource.publicKey,
              mlKemPublicKey: 'mlkem-${repairSource.peerId}',
              joinedAt: DateTime.now().toUtc(),
            ),
          );
        }

        final readerBridge = reader.bridge as _CursorInboxBridge;
        final historyRepo = _InMemoryGroupHistoryGapRepairRepository();
        final repairedPayloads = [
          {
            'groupId': groupId,
            'senderId': admin.peerId,
            'senderUsername': admin.username,
            'keyEpoch': 1,
            'text': 'Recovered gap message one',
            'timestamp': DateTime.utc(2026, 5, 1, 12, 1).toIso8601String(),
            'messageId': 'repaired-gap-1',
          },
          {
            'groupId': groupId,
            'senderId': admin.peerId,
            'senderUsername': admin.username,
            'keyEpoch': 1,
            'text': 'Recovered gap message two',
            'timestamp': DateTime.utc(2026, 5, 1, 12, 2).toIso8601String(),
            'messageId': 'repaired-gap-2',
          },
        ];
        final repairedMessages = <Map<String, dynamic>>[];
        for (final payload in repairedPayloads) {
          repairedMessages.add(
            await _signedReplayRelayMessage(
              bridge: reader.bridge,
              groupRepo: reader.groupRepo,
              groupId: groupId,
              payload: payload,
              senderPeerId: admin.peerId,
              senderPublicKey: admin.publicKey,
              senderPrivateKey: admin.privateKey,
            ),
          );
        }
        final rangeHash = computeGroupHistoryRangeHash(repairedMessages);

        readerBridge.addPage(
          groupId,
          '',
          [],
          '',
          historyGaps: [
            {
              'groupId': groupId,
              'gapId': 'gap-1',
              'missingAfterMessageId': 'msg-before',
              'missingBeforeMessageId': 'msg-after',
              'expectedRangeHash': rangeHash,
              'expectedHeadMessageId': 'msg-after',
              'candidateSourcePeerIds': [
                'rogue-peer',
                source.peerId,
                headSource.peerId,
                admin.peerId,
              ],
            },
          ],
        );
        readerBridge.addRepairResponse(
          groupId: groupId,
          gapId: 'gap-1',
          sourcePeerId: source.peerId,
          response: {
            'ok': true,
            'groupId': groupId,
            'gapId': 'gap-1',
            'sourcePeerId': source.peerId,
            'rangeHash': 'wrong-hash',
            'headMessageId': 'msg-after',
            'messages': repairedMessages.take(1).toList(),
          },
        );
        readerBridge.addRepairResponse(
          groupId: groupId,
          gapId: 'gap-1',
          sourcePeerId: headSource.peerId,
          response: {
            'ok': true,
            'groupId': groupId,
            'gapId': 'gap-1',
            'sourcePeerId': headSource.peerId,
            'rangeHash': rangeHash,
            'headMessageId': 'wrong-head',
            'messages': repairedMessages,
          },
        );
        readerBridge.addRepairResponse(
          groupId: groupId,
          gapId: 'gap-1',
          sourcePeerId: admin.peerId,
          response: {
            'ok': true,
            'groupId': groupId,
            'gapId': 'gap-1',
            'sourcePeerId': admin.peerId,
            'rangeHash': rangeHash,
            'headMessageId': 'msg-after',
            'messages': repairedMessages,
          },
        );

        await drainGroupOfflineInbox(
          bridge: reader.bridge,
          groupRepo: reader.groupRepo,
          msgRepo: reader.msgRepo,
          historyGapRepairRepo: historyRepo,
        );
        await handleIncomingGroupMessage(
          groupRepo: reader.groupRepo,
          msgRepo: reader.msgRepo,
          groupId: groupId,
          senderId: admin.peerId,
          senderUsername: admin.username,
          keyEpoch: 1,
          text: 'Live after repair',
          timestamp: DateTime.utc(2026, 5, 1, 12, 3).toIso8601String(),
          messageId: 'live-after-repair',
        );

        final repair = await historyRepo.getRepair(
          groupId: groupId,
          gapId: 'gap-1',
        );
        expect(repair!.status, groupHistoryGapRepairStatusRepaired);
        expect(
          repair.attemptedSourcePeerIds,
          containsAll([
            'rogue-peer',
            source.peerId,
            headSource.peerId,
            admin.peerId,
          ]),
        );
        expect(repair.repairedMessageIds, ['repaired-gap-1', 'repaired-gap-2']);
        final messages = await reader.msgRepo.getMessagesPage(groupId);
        expect(messages.map((message) => message.id), [
          'repaired-gap-1',
          'repaired-gap-2',
          'live-after-repair',
        ]);
      },
    );

    test(
      'IR-013 fake-network unauthorized repair source cannot inject before fallback',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'ir013-admin-peer',
          username: 'Admin',
          network: network,
        );
        final reader = GroupTestUser.create(
          peerId: 'ir013-reader-peer',
          username: 'Reader',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final source = GroupTestUser.create(
          peerId: 'ir013-source-peer',
          username: 'Source',
          network: network,
        );
        final fallbackSource = GroupTestUser.create(
          peerId: 'ir013-fallback-peer',
          username: 'Fallback',
          network: network,
        );

        const groupId = 'ir013-history-gap-group';
        await admin.createGroup(groupId: groupId, name: 'IR013 History Gap');
        await admin.addMember(groupId: groupId, invitee: reader);
        await reader.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'ir013-history-gap-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );
        for (final repairSource in [source, fallbackSource]) {
          await reader.groupRepo.saveMember(
            GroupMember(
              groupId: groupId,
              peerId: repairSource.peerId,
              username: repairSource.username,
              role: MemberRole.reader,
              publicKey: repairSource.publicKey,
              mlKemPublicKey: 'mlkem-${repairSource.peerId}',
              joinedAt: DateTime.now().toUtc(),
            ),
          );
        }

        final readerBridge = reader.bridge as _CursorInboxBridge;
        final historyRepo = _InMemoryGroupHistoryGapRepairRepository();
        final repairedMessages = [
          await _signedReplayRelayMessage(
            bridge: reader.bridge,
            groupRepo: reader.groupRepo,
            groupId: groupId,
            payload: {
              'groupId': groupId,
              'senderId': admin.peerId,
              'senderUsername': admin.username,
              'keyEpoch': 1,
              'text': 'IR013 authorized fallback repair',
              'timestamp': DateTime.utc(2026, 5, 1, 12, 4).toIso8601String(),
              'messageId': 'ir013-repaired-good',
            },
            senderPeerId: admin.peerId,
            senderPublicKey: admin.publicKey,
            senderPrivateKey: admin.privateKey,
          ),
        ];
        final rangeHash = computeGroupHistoryRangeHash(repairedMessages);

        readerBridge.addPage(
          groupId,
          '',
          [],
          '',
          historyGaps: [
            {
              'groupId': groupId,
              'gapId': 'gap-1',
              'missingAfterMessageId': 'msg-before',
              'missingBeforeMessageId': 'msg-after',
              'expectedRangeHash': rangeHash,
              'expectedHeadMessageId': 'msg-after',
              'candidateSourcePeerIds': [
                'ir013-rogue-peer',
                source.peerId,
                fallbackSource.peerId,
              ],
            },
          ],
        );
        readerBridge.addRepairResponse(
          groupId: groupId,
          gapId: 'gap-1',
          sourcePeerId: 'ir013-rogue-peer',
          response: {
            'ok': true,
            'groupId': groupId,
            'gapId': 'gap-1',
            'sourcePeerId': 'ir013-rogue-peer',
            'rangeHash': rangeHash,
            'headMessageId': 'msg-after',
            'messages': repairedMessages,
          },
        );
        readerBridge.addRepairResponse(
          groupId: groupId,
          gapId: 'gap-1',
          sourcePeerId: source.peerId,
          response: {
            'ok': true,
            'groupId': groupId,
            'gapId': 'gap-1',
            'sourcePeerId': 'ir013-rogue-peer',
            'rangeHash': rangeHash,
            'headMessageId': 'msg-after',
            'messages': repairedMessages,
          },
        );
        readerBridge.addRepairResponse(
          groupId: groupId,
          gapId: 'gap-1',
          sourcePeerId: fallbackSource.peerId,
          response: {
            'ok': true,
            'groupId': groupId,
            'gapId': 'gap-1',
            'sourcePeerId': fallbackSource.peerId,
            'rangeHash': rangeHash,
            'headMessageId': 'msg-after',
            'messages': repairedMessages,
          },
        );

        await drainGroupOfflineInbox(
          bridge: reader.bridge,
          groupRepo: reader.groupRepo,
          msgRepo: reader.msgRepo,
          historyGapRepairRepo: historyRepo,
        );

        final repair = await historyRepo.getRepair(
          groupId: groupId,
          gapId: 'gap-1',
        );
        expect(repair!.status, groupHistoryGapRepairStatusRepaired);
        expect(
          repair.attemptedSourcePeerIds,
          containsAll([
            'ir013-rogue-peer',
            source.peerId,
            fallbackSource.peerId,
          ]),
        );
        expect(repair.repairedMessageIds, ['ir013-repaired-good']);
        expect(repair.failureReason, isNull);

        final repairRequests = bridgePayloads(
          reader.bridge,
          'group:historyRepairRange',
        );
        expect(
          repairRequests.map((payload) => payload['sourcePeerId']).toList(),
          [source.peerId, fallbackSource.peerId],
        );
        expect(
          repairRequests.map((payload) => payload['sourcePeerId']),
          isNot(contains('ir013-rogue-peer')),
        );
        final messages = await reader.msgRepo.getMessagesPage(groupId);
        expect(messages.map((message) => message.id), ['ir013-repaired-good']);
      },
    );

    test(
      'IR-014 fake-network inbox store relay payload is opaque while delivery succeeds',
      () async {
        final aliceBridge = _OpaqueReplayBridge();
        final alice = GroupTestUser.create(
          peerId: 'ir014-alice-peer',
          username: 'IR014 Alice Secret Name',
          network: network,
          bridge: aliceBridge,
        );
        final bob = GroupTestUser.create(
          peerId: 'ir014-bob-peer',
          username: 'Bob',
          network: network,
        );

        const groupId = 'ir014-opaque-relay-group';
        const groupKey = 'ir014-group-key-secret';
        const protectedText = 'IR014 relay plaintext alpha';
        const inviteSecret = 'ir014-invite-secret-beta';
        const memberSecret = 'ir014-member-secret-gamma';
        final protectedFragments = [
          protectedText,
          alice.username,
          groupKey,
          inviteSecret,
          memberSecret,
        ];

        await alice.createGroup(groupId: groupId, name: 'IR014 Opaque Relay');
        await alice.addMember(groupId: groupId, invitee: bob);
        await _saveKey(alice, groupId, 1, groupKey);
        await _saveKey(bob, groupId, 1, groupKey);

        alice.start();
        bob.start();

        final (result, sent) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: '$protectedText $inviteSecret $memberSecret',
          messageId: 'ir014-opaque-live',
          timestamp: DateTime.utc(2026, 5, 1, 12, 5),
        );
        expect(result, SendGroupMessageResult.success);
        expect(sent, isNotNull);

        await pumpUntilAsync(() async {
          final bobMessages = await bob.loadGroupMessages(groupId);
          return bobMessages.any(
            (message) => message.id == 'ir014-opaque-live',
          );
        });
        final bobMessages = await bob.loadGroupMessages(groupId);
        expect(
          bobMessages
              .singleWhere((message) => message.id == 'ir014-opaque-live')
              .text,
          '$protectedText $inviteSecret $memberSecret',
        );

        final inboxStoreCommand = alice.bridge.sentMessages.lastWhere(
          (raw) =>
              (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:inboxStore',
        );
        for (final fragment in protectedFragments) {
          expect(inboxStoreCommand, isNot(contains(fragment)));
        }

        final inboxPayload = latestBridgePayload(
          alice.bridge,
          'group:inboxStore',
        );
        expect(inboxPayload.keys.toSet(), {
          'groupId',
          'message',
          'recipientPeerIds',
        });
        expect(inboxPayload['groupId'], groupId);
        expect(inboxPayload['recipientPeerIds'], [bob.peerId]);

        final replayEnvelope =
            jsonDecode(inboxPayload['message'] as String)
                as Map<String, dynamic>;
        expect(replayEnvelope['kind'], 'group_offline_replay');
        expect(replayEnvelope['payloadType'], 'group_message');
        expect(replayEnvelope['messageId'], 'ir014-opaque-live');
        expect(replayEnvelope['ciphertext'], startsWith('sealed:'));
        expect(replayEnvelope['nonce'], 'ir014-opaque-replay-nonce');
        expect(replayEnvelope.containsKey('text'), isFalse);
        expect(replayEnvelope.containsKey('senderUsername'), isFalse);
        for (final fragment in protectedFragments) {
          expect(
            replayEnvelope['signedPayload'] as String,
            isNot(contains(fragment)),
          );
        }
      },
    );

    test(
      'IR-015 fake-network replay drains text quote image video file GIF and voice uniformly',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ir015-alice-peer',
          username: 'IR015 Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ir015-bob-peer',
          username: 'IR015 Bob',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final charlie = GroupTestUser.create(
          peerId: 'ir015-charlie-peer',
          username: 'IR015 Charlie',
          network: network,
        );
        final bobBridge = bob.bridge as _CursorInboxBridge;

        const groupId = 'ir015-variant-replay-group';
        await alice.createGroup(groupId: groupId, name: 'IR015 Variants');
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);
        await _saveKey(alice, groupId, 1, 'ir015-k1');
        await _saveKey(bob, groupId, 1, 'ir015-k1');
        await _saveKey(charlie, groupId, 1, 'ir015-k1');

        alice.start();
        bob.start();
        charlie.start();
        network.unsubscribe(groupId, bob.peerId);

        final sentByKey = <String, GroupMessage>{};
        Future<void> sendVariant({
          required String key,
          required String text,
          String? quotedMessageId,
          List<MediaAttachment>? media,
        }) async {
          final (result, sent) = await alice.sendGroupMessageViaBridge(
            groupId: groupId,
            text: text,
            messageId: key,
            quotedMessageId: quotedMessageId,
            mediaAttachments: media,
            publishTopicPeersOverride: 1,
          );
          expect(result, SendGroupMessageResult.success);
          expect(sent, isNotNull);
          expect(sent!.keyGeneration, 1);
          sentByKey[key] = sent;
        }

        await sendVariant(key: 'ir015-text', text: 'IR-015 text');
        await sendVariant(
          key: 'ir015-quote',
          text: 'IR-015 quote',
          quotedMessageId: sentByKey['ir015-text']!.id,
        );
        await sendVariant(
          key: 'ir015-image',
          text: '',
          media: [
            _uploadedMedia(
              id: 'ir015-image-att',
              messageId: '',
              mime: 'image/jpeg',
              localPath: 'media/ir015/image.jpg',
              width: 1280,
              height: 720,
            ),
          ],
        );
        await sendVariant(
          key: 'ir015-video',
          text: '',
          media: [
            _uploadedMedia(
              id: 'ir015-video-att',
              messageId: '',
              mime: 'video/mp4',
              localPath: 'media/ir015/video.mp4',
              width: 1920,
              height: 1080,
              durationMs: 4200,
            ),
          ],
        );
        await sendVariant(
          key: 'ir015-file',
          text: '',
          media: [
            _uploadedMedia(
              id: 'ir015-file-att',
              messageId: '',
              mime: 'application/octet-stream',
              localPath: 'media/ir015/file.bin',
            ),
          ],
        );
        await sendVariant(
          key: 'ir015-gif',
          text: '',
          media: [
            _uploadedMedia(
              id: 'ir015-gif-att',
              messageId: '',
              mime: 'image/gif',
              localPath: 'media/ir015/anim.gif',
              width: 640,
              height: 360,
            ),
          ],
        );
        await sendVariant(
          key: 'ir015-voice',
          text: '',
          media: [
            _uploadedMedia(
              id: 'ir015-voice-att',
              messageId: '',
              mime: 'audio/mp4',
              localPath: 'media/ir015/voice.m4a',
              durationMs: 3100,
              waveform: const [0.1, 0.4, 0.8, 0.3],
            ),
          ],
        );

        await pumpUntilAsync(() async {
          final charlieMessages = await charlie.loadGroupMessages(groupId);
          final ids = charlieMessages.map((message) => message.id).toSet();
          return sentByKey.keys.every(ids.contains);
        });
        expect(await bob.loadGroupMessages(groupId), isEmpty);

        final sentIds = sentByKey.values.map((message) => message.id).toSet();
        final storePayloads = bridgePayloads(alice.bridge, 'group:inboxStore')
            .where((payload) {
              final envelope =
                  jsonDecode(payload['message'] as String)
                      as Map<String, dynamic>;
              return sentIds.contains(envelope['messageId']);
            })
            .toList(growable: false);
        expect(storePayloads, hasLength(sentIds.length));
        bobBridge.addPage(groupId, '', [
          for (var i = 0; i < storePayloads.length; i++)
            {
              'from': alice.peerId,
              'message': storePayloads[i]['message'] as String,
              'timestamp': i + 1,
            },
        ], '');

        for (final payload in storePayloads) {
          expect(
            (payload['recipientPeerIds'] as List<dynamic>).cast<String>(),
            contains(bob.peerId),
          );
        }

        await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          mediaAttachmentRepo: bob.mediaAttachmentRepo,
        );
        await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          mediaAttachmentRepo: bob.mediaAttachmentRepo,
        );

        final bobMessages = await bob.loadGroupMessages(groupId);
        expect(bobMessages, hasLength(sentIds.length));
        expect(bobMessages.map((message) => message.id).toSet(), sentIds);
        expect(
          bobMessages
              .singleWhere((message) => message.id == 'ir015-quote')
              .quotedMessageId,
          sentByKey['ir015-text']!.id,
        );
        expect(
          bobMessages.every((message) => message.keyGeneration == 1),
          isTrue,
        );

        Future<MediaAttachment> onlyAttachment(String messageId) async {
          final attachments = await bob.mediaAttachmentRepo
              .getAttachmentsForMessage(messageId);
          expect(attachments, hasLength(1));
          return attachments.single;
        }

        expect((await onlyAttachment('ir015-image')).mediaType, 'image');
        final video = await onlyAttachment('ir015-video');
        expect(video.mediaType, 'video');
        expect(video.durationMs, 4200);
        expect((await onlyAttachment('ir015-file')).mediaType, 'file');
        expect((await onlyAttachment('ir015-gif')).mime, 'image/gif');
        final voice = await onlyAttachment('ir015-voice');
        expect(voice.mediaType, 'audio');
        expect(voice.durationMs, 3100);
        expect(voice.waveform, const [0.1, 0.4, 0.8, 0.3]);
      },
    );

    test(
      'IR-019 fake-network replay dedupes by decrypted payload id without outer id',
      () async {
        final adminBridge = _Section10MirroringBridge(
          network: network,
          msgRepo: InMemoryGroupMessageRepository(),
          groupRepo: InMemoryGroupRepository(),
        );
        final admin = GroupTestUser.create(
          peerId: 'admin-ir019-peer',
          username: 'Alice',
          network: network,
          bridge: adminBridge,
        );
        final bob = GroupTestUser.create(
          peerId: 'reader-ir019-peer',
          username: 'Bob',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final bobBridge = bob.bridge as _CursorInboxBridge;
        final emitted = <GroupMessage>[];
        final subscription = bob.groupMessageListener.groupMessageStream.listen(
          emitted.add,
        );
        addTearDown(() async {
          await subscription.cancel();
          admin.dispose();
          bob.dispose();
        });

        const groupId = 'group-ir019-hidden-id';
        const messageId = 'ir019-live-hidden-replay';
        final sentAt = DateTime.utc(2026, 5, 1, 12);
        await admin.createGroup(groupId: groupId, name: 'IR019 Hidden Id');
        await admin.addMember(groupId: groupId, invitee: bob);
        await _saveKey(admin, groupId, 1, 'k1');
        await _saveKey(bob, groupId, 1, 'k1');

        admin.start();
        bob.start();

        final (sendResult, sentMessage) = await admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'IR-019 trusted live content',
          messageId: messageId,
          timestamp: sentAt,
        );
        expect(sendResult, SendGroupMessageResult.success);
        expect(sentMessage, isNotNull);
        await pumpUntilAsync(
          () async => (await bob.msgRepo.getMessage(messageId)) != null,
        );
        await pump();

        final liveRow = await bob.msgRepo.getMessage(messageId);
        expect(liveRow, isNotNull);
        expect(liveRow!.text, 'IR-019 trusted live content');
        expect(
          emitted.where((message) => message.id == messageId),
          hasLength(1),
        );

        final replayPayload = {
          'groupId': groupId,
          'senderId': admin.peerId,
          'senderUsername': admin.username,
          'keyEpoch': 1,
          'text': 'IR-019 conflicting hidden replay',
          'timestamp': sentAt.add(const Duration(minutes: 5)).toIso8601String(),
          'messageId': messageId,
        };
        final replayRelayMessage = await _signedReplayRelayMessage(
          bridge: admin.bridge,
          groupRepo: bob.groupRepo,
          groupId: groupId,
          payload: replayPayload,
          senderPeerId: admin.peerId,
          senderPublicKey: admin.publicKey,
          senderPrivateKey: admin.privateKey,
          includeEnvelopeMessageId: false,
        );
        expect(replayRelayMessage.keys.toSet(), {
          'from',
          'message',
          'timestamp',
        });
        expect(replayRelayMessage.containsKey('id'), isFalse);
        expect(replayRelayMessage.containsKey('messageId'), isFalse);
        final replayEnvelope =
            jsonDecode(replayRelayMessage['message'] as String)
                as Map<String, dynamic>;
        expect(replayEnvelope.containsKey('messageId'), isFalse);

        bobBridge.addPage(groupId, '', [
          replayRelayMessage,
        ], 'cursor-ir019-hidden-id');

        await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          groupMessageListener: bob.groupMessageListener,
          mediaAttachmentRepo: bob.mediaAttachmentRepo,
          selfPeerId: bob.peerId,
          drainAllPages: false,
        );
        await pump();

        final bobMessages = await bob.loadGroupMessages(groupId);
        final matchingRows = bobMessages
            .where((message) => message.id == messageId && message.isIncoming)
            .toList(growable: false);
        expect(matchingRows, hasLength(1));
        expect(matchingRows.single.text, 'IR-019 trusted live content');
        expect(matchingRows.single.timestamp, liveRow.timestamp);
        expect(
          emitted.where((message) => message.id == messageId),
          hasLength(1),
          reason: 'Hidden-id replay must not emit a duplicate UI row',
        );
        expect(
          await bob.msgRepo.getInboxCursor(groupId),
          'cursor-ir019-hidden-id',
        );
      },
    );

    test(
      'DE-004 live plus inbox replay duplicate keeps one row and commits replay evidence',
      () async {
        final adminBridge = _Section10MirroringBridge(
          network: network,
          msgRepo: InMemoryGroupMessageRepository(),
          groupRepo: InMemoryGroupRepository(),
        );
        final admin = GroupTestUser.create(
          peerId: 'admin-de004-peer',
          username: 'Alice',
          network: network,
          bridge: adminBridge,
        );
        final bob = GroupTestUser.create(
          peerId: 'reader-de004-peer',
          username: 'Bob',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final bobBridge = bob.bridge as _CursorInboxBridge;
        final emitted = <GroupMessage>[];
        final subscription = bob.groupMessageListener.groupMessageStream.listen(
          emitted.add,
        );
        addTearDown(() async {
          await subscription.cancel();
          admin.dispose();
          bob.dispose();
        });

        const groupId = 'group-de004-live-replay';
        const messageId = 'de004-live-network-message';
        final sentAt = DateTime.utc(2026, 5, 1, 12);
        await admin.createGroup(groupId: groupId, name: 'DE-004 Group');
        await admin.addMember(groupId: groupId, invitee: bob);
        await _saveKey(admin, groupId, 1, 'k1');
        await _saveKey(bob, groupId, 1, 'k1');

        admin.start();
        bob.start();

        final (sendResult, sentMessage) = await admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'Trusted network live content',
          messageId: messageId,
          timestamp: sentAt,
        );
        expect(sendResult, SendGroupMessageResult.success);
        expect(sentMessage, isNotNull);
        await pumpUntilAsync(
          () async => (await bob.msgRepo.getMessage(messageId)) != null,
        );
        await pump();

        expect(
          emitted.where((message) => message.id == messageId),
          hasLength(1),
        );
        final liveRow = await bob.msgRepo.getMessage(messageId);
        expect(liveRow, isNotNull);
        expect(liveRow!.text, 'Trusted network live content');
        expect(liveRow.senderPeerId, admin.peerId);
        expect(liveRow.status, 'delivered');
        final liveTimestamp = liveRow.timestamp;

        final storedPayload = _decodedGroupReplayPayload(
          latestBridgePayload(admin.bridge, 'group:inboxStore')['message']
              as String,
        );
        expect(storedPayload['messageId'], messageId);
        final replayPayload = Map<String, dynamic>.from(storedPayload)
          ..['text'] = 'Conflicting replay content'
          ..['timestamp'] = liveTimestamp
              .add(const Duration(minutes: 5))
              .toIso8601String()
          ..['receipts'] = [
            {
              'messageId': messageId,
              'receiptType': groupMessageReceiptTypeRead,
              'memberPeerId': bob.peerId,
              'receiptAt': '2026-05-01T12:06:00.000Z',
              'sourceEventId': 'de004-network-replay-read',
            },
          ];
        bobBridge.addPage(groupId, '', [
          await _signedReplayRelayMessage(
            bridge: admin.bridge,
            groupRepo: bob.groupRepo,
            groupId: groupId,
            payload: replayPayload,
            senderPeerId: admin.peerId,
            senderPublicKey: admin.publicKey,
            senderPrivateKey: admin.privateKey,
          ),
        ], 'cursor-de004-network');

        await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          groupMessageListener: bob.groupMessageListener,
          mediaAttachmentRepo: bob.mediaAttachmentRepo,
          selfPeerId: bob.peerId,
          drainAllPages: false,
        );
        await pump();

        final bobMessages = await bob.loadGroupMessages(groupId);
        final matchingRows = bobMessages
            .where((message) => message.id == messageId && message.isIncoming)
            .toList();
        expect(matchingRows, hasLength(1));
        expect(matchingRows.single.text, 'Trusted network live content');
        expect(matchingRows.single.timestamp, liveTimestamp);
        expect(matchingRows.single.senderPeerId, admin.peerId);
        expect(matchingRows.single.status, 'delivered');
        expect(matchingRows.single.readAt, isNotNull);
        expect(
          emitted.where((message) => message.id == messageId),
          hasLength(1),
          reason: 'Duplicate replay must not emit a second live UI row',
        );
        expect(
          await bob.msgRepo.getInboxCursor(groupId),
          'cursor-de004-network',
        );

        final readReceipts = await bob.msgRepo.getReceiptsForMessage(
          groupId,
          messageId,
          receiptType: groupMessageReceiptTypeRead,
        );
        expect(readReceipts, hasLength(1));
        expect(readReceipts.single.memberPeerId, bob.peerId);
        expect(readReceipts.single.sourceEventId, 'de004-network-replay-read');

        final deliveredReceipts = await bob.msgRepo.getReceiptsForMessage(
          groupId,
          messageId,
          receiptType: groupMessageReceiptTypeDelivered,
        );
        expect(deliveredReceipts, hasLength(1));
        expect(deliveredReceipts.single.memberPeerId, bob.peerId);
        expect(
          deliveredReceipts.single.sourceEventId,
          'local-delivered:$groupId:$messageId',
        );
      },
    );

    test(
      'DE-005 sender self echo plus inbox duplicate reconciles pending row once',
      () async {
        final sender = GroupTestUser.create(
          peerId: 'sender-de005-peer',
          username: 'Sender',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final senderBridge = sender.bridge as _CursorInboxBridge;
        final emitted = <GroupMessage>[];
        final subscription = sender.groupMessageListener.groupMessageStream
            .listen(emitted.add);
        addTearDown(() async {
          await subscription.cancel();
          sender.dispose();
        });

        const groupId = 'group-de005-self-echo';
        const messageId = 'de005-sender-self-echo';
        final sentAt = DateTime.utc(2026, 5, 11, 10, 10);
        await sender.createGroup(groupId: groupId, name: 'DE-005 Group');
        await _saveKey(sender, groupId, 1, 'k1');
        sender.start();

        await sender.msgRepo.saveMessage(
          GroupMessage(
            id: messageId,
            groupId: groupId,
            senderPeerId: sender.peerId,
            transportPeerId: sender.deviceId,
            senderUsername: sender.username,
            text: 'Local sender pending text',
            timestamp: sentAt,
            keyGeneration: 1,
            status: 'pending',
            isIncoming: false,
            createdAt: sentAt,
            wireEnvelope: '{"cmd":"group:publish"}',
            inboxRetryPayload: '{"cmd":"group:inboxStore"}',
          ),
        );

        await sender.groupMessageListener.handleReplayEnvelope({
          'groupId': groupId,
          'senderId': sender.peerId,
          'senderUsername': sender.username,
          'keyEpoch': 1,
          'text': 'Local sender pending text',
          'timestamp': sentAt.add(const Duration(seconds: 3)).toIso8601String(),
          'messageId': messageId,
          'transportPeerId': sender.deviceId,
          'senderDeviceId': sender.deviceId,
        }, rethrowOnError: true);
        await pump();

        expect(
          emitted.where((message) => message.id == messageId),
          hasLength(1),
          reason: 'Self echo should emit the reconciled outbound row once',
        );
        var senderMessages = await sender.loadGroupMessages(groupId);
        var matchingRows = senderMessages
            .where((message) => message.id == messageId)
            .toList();
        expect(matchingRows, hasLength(1));
        expect(matchingRows.single.isIncoming, isFalse);
        expect(matchingRows.single.status, 'sent');
        expect(matchingRows.single.text, 'Local sender pending text');
        expect(matchingRows.single.timestamp, sentAt);

        final replayPayload = {
          'groupId': groupId,
          'senderId': sender.peerId,
          'senderUsername': sender.username,
          'keyEpoch': 1,
          'text': 'Conflicting replay text',
          'timestamp': sentAt.add(const Duration(minutes: 5)).toIso8601String(),
          'messageId': messageId,
          'transportPeerId': sender.deviceId,
          'senderDeviceId': sender.deviceId,
        };
        senderBridge.addPage(groupId, '', [
          await _signedReplayRelayMessage(
            bridge: sender.bridge,
            groupRepo: sender.groupRepo,
            groupId: groupId,
            payload: replayPayload,
            senderPeerId: sender.peerId,
            senderPublicKey: sender.publicKey,
            senderPrivateKey: sender.privateKey,
          ),
        ], 'cursor-de005-self');

        await drainGroupOfflineInbox(
          bridge: sender.bridge,
          groupRepo: sender.groupRepo,
          msgRepo: sender.msgRepo,
          groupMessageListener: sender.groupMessageListener,
          mediaAttachmentRepo: sender.mediaAttachmentRepo,
          selfPeerId: sender.peerId,
          drainAllPages: false,
        );
        await pump();

        senderMessages = await sender.loadGroupMessages(groupId);
        matchingRows = senderMessages
            .where((message) => message.id == messageId)
            .toList();
        expect(matchingRows, hasLength(1));
        expect(matchingRows.single.isIncoming, isFalse);
        expect(matchingRows.single.status, 'sent');
        expect(matchingRows.single.text, 'Local sender pending text');
        expect(matchingRows.single.timestamp, sentAt);
        expect(
          emitted.where((message) => message.id == messageId),
          hasLength(1),
          reason: 'Inbox duplicate must not emit a second visible row',
        );
        expect(await sender.msgRepo.getUnreadCount(groupId), 0);
        expect(
          await sender.msgRepo.getInboxCursor(groupId),
          'cursor-de005-self',
        );
        final deliveredReceipts = await sender.msgRepo.getReceiptsForMessage(
          groupId,
          messageId,
          receiptType: groupMessageReceiptTypeDelivered,
        );
        expect(deliveredReceipts, isEmpty);
      },
    );

    test(
      'live reaction replay on resume keeps a single truthful stored reaction after rejoin',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-reaction-resume-peer',
          username: 'Admin',
          network: network,
          bridge: _CursorInboxBridge(),
          reactionRepo: FakeReactionRepository(),
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-reaction-resume-peer',
          username: 'Bob',
          network: network,
          reactionRepo: FakeReactionRepository(),
        );
        final adminBridge = admin.bridge as _CursorInboxBridge;

        const groupId = 'group-reaction-resume';
        final joinedAt = DateTime.now().toUtc();

        await admin.createGroup(groupId: groupId, name: 'Reaction Resume');
        await admin.addMember(groupId: groupId, invitee: bob);

        Future<void> saveKey(GroupTestUser user, int generation) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: generation,
              encryptedKey: 'k$generation',
              createdAt: joinedAt,
            ),
          );
        }

        await saveKey(admin, 1);
        await saveKey(bob, 1);

        admin.start();
        bob.start();

        final (sendResult, sentMessage) = await admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'Reaction target',
        );
        expect(sendResult, SendGroupMessageResult.success);
        expect(sentMessage, isNotNull);

        await pump();
        final bobMessages = await bob.loadGroupMessages(groupId);
        final received = bobMessages.firstWhere(
          (message) => message.id == sentMessage!.id,
        );

        final liveReactionChange =
            admin.groupMessageListener.groupReactionChangeStream.first;
        final (reactionResult, reaction) = await bob.sendGroupReactionViaBridge(
          groupId: groupId,
          messageId: received.id,
          emoji: '🔥',
        );
        expect(reactionResult, group_react.SendGroupReactionResult.success);
        expect(reaction, isNotNull);

        final liveChange = await liveReactionChange;
        expect(liveChange.messageId, received.id);
        expect(liveChange.senderPeerId, bob.peerId);

        var adminReactions = await admin.reactionRepo!.getReactionsForMessage(
          received.id,
        );
        expect(adminReactions, hasLength(1));
        expect(adminReactions.single.emoji, '🔥');
        expect(adminReactions.single.senderPeerId, bob.peerId);

        final inboxPayload = latestBridgePayload(
          bob.bridge,
          'group:inboxStore',
        );
        final replayMessage = inboxPayload['message'] as String;
        final replayEnvelope = _storedGroupReplayEnvelope(replayMessage);
        expect(replayEnvelope['kind'], 'group_offline_replay');
        expect(replayEnvelope['payloadType'], 'group_reaction');

        network.unsubscribe(groupId, admin.peerId);
        adminBridge.addPage(groupId, '', [
          {
            'from': bob.peerId,
            'message': replayMessage,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        ], '');

        await rejoinGroupTopics(
          bridge: admin.bridge,
          groupRepo: admin.groupRepo,
          reason: RejoinReason.startup,
        );
        network.subscribe(groupId, admin.peerId);

        await drainGroupOfflineInbox(
          bridge: admin.bridge,
          groupRepo: admin.groupRepo,
          msgRepo: admin.msgRepo,
          reactionRepo: admin.reactionRepo,
        );

        adminReactions = await admin.reactionRepo!.getReactionsForMessage(
          received.id,
        );
        expect(adminReactions, hasLength(1));
        expect(adminReactions.single.emoji, '🔥');
        expect(adminReactions.single.senderPeerId, bob.peerId);
        expect(admin.bridge.commandLog, contains('group:join'));

        admin.dispose();
        bob.dispose();
      },
    );

    test(
      'post-rotation reaction replay after rejoin keeps the truthful reactor on the rotated message',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-reaction-rotation-peer',
          username: 'Admin',
          network: network,
          bridge: _CursorInboxBridge(),
          reactionRepo: FakeReactionRepository(),
        );
        final reader = GroupTestUser.create(
          peerId: 'reader-reaction-rotation-peer',
          username: 'Reader',
          network: network,
          reactionRepo: FakeReactionRepository(),
        );
        final adminBridge = admin.bridge as _CursorInboxBridge;

        const groupId = 'group-reaction-rotation';
        final joinedAt = DateTime.now().toUtc();

        await admin.createGroup(groupId: groupId, name: 'Reaction Rotation');
        await admin.addMember(groupId: groupId, invitee: reader);

        Future<void> saveKey(GroupTestUser user, int generation) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: generation,
              encryptedKey: 'k$generation',
              createdAt: joinedAt,
            ),
          );
        }

        await saveKey(admin, 1);
        await saveKey(reader, 1);

        admin.start();
        reader.start();

        await saveKey(admin, 2);
        await saveKey(reader, 2);

        final (sendResult, sentMessage) = await admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'After rotation reaction target',
        );
        expect(sendResult, SendGroupMessageResult.success);
        expect(sentMessage, isNotNull);
        expect(sentMessage!.keyGeneration, 2);

        await pump();
        final readerMessages = await reader.loadGroupMessages(groupId);
        final delivered = readerMessages.firstWhere(
          (message) => message.id == sentMessage.id,
        );
        expect(delivered.keyGeneration, 2);

        network.unsubscribe(groupId, admin.peerId);

        final (reactionResult, reaction) = await reader
            .sendGroupReactionViaBridge(
              groupId: groupId,
              messageId: delivered.id,
              emoji: '👍',
            );
        expect(reactionResult, group_react.SendGroupReactionResult.success);
        expect(reaction, isNotNull);

        final inboxPayload = latestBridgePayload(
          reader.bridge,
          'group:inboxStore',
        );
        final replayMessage = inboxPayload['message'] as String;
        final replayEnvelope = _storedGroupReplayEnvelope(replayMessage);
        expect(replayEnvelope['kind'], 'group_offline_replay');
        expect(replayEnvelope['payloadType'], 'group_reaction');

        adminBridge.addPage(groupId, '', [
          {
            'from': reader.peerId,
            'message': replayMessage,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        ], '');
        expect(
          await admin.reactionRepo!.getReactionsForMessage(delivered.id),
          isEmpty,
        );

        await rejoinGroupTopics(
          bridge: admin.bridge,
          groupRepo: admin.groupRepo,
          reason: RejoinReason.startup,
        );
        network.subscribe(groupId, admin.peerId);

        await drainGroupOfflineInbox(
          bridge: admin.bridge,
          groupRepo: admin.groupRepo,
          msgRepo: admin.msgRepo,
          reactionRepo: admin.reactionRepo,
        );

        final recoveredReactions = await admin.reactionRepo!
            .getReactionsForMessage(delivered.id);
        expect(recoveredReactions, hasLength(1));
        expect(recoveredReactions.single.emoji, '👍');
        expect(recoveredReactions.single.senderPeerId, reader.peerId);
        expect(admin.bridge.commandLog, contains('group:join'));

        admin.dispose();
        reader.dispose();
      },
    );

    test(
      'resume retry replays failed reaction add/remove stores and converges to the final removed state',
      () async {
        final adminBridge = _Section10MirroringBridge(
          network: network,
          msgRepo: InMemoryGroupMessageRepository(),
          groupRepo: InMemoryGroupRepository(),
        );
        final admin = GroupTestUser.create(
          peerId: 'admin-reaction-retry-peer',
          username: 'Admin',
          network: network,
          bridge: adminBridge,
          reactionRepo: FakeReactionRepository(),
        );
        final reader = GroupTestUser.create(
          peerId: 'reader-reaction-retry-peer',
          username: 'Reader',
          network: network,
          bridge: _CursorInboxBridge(),
          reactionRepo: FakeReactionRepository(),
        );
        final readerBridge = reader.bridge as _CursorInboxBridge;

        const groupId = 'group-reaction-retry-resume';
        await admin.createGroup(groupId: groupId, name: 'Reaction Retry');
        await admin.addMember(groupId: groupId, invitee: reader);
        await _saveKey(admin, groupId, 1, 'k1');
        await _saveKey(reader, groupId, 1, 'k1');

        admin.start();
        reader.start();

        final (sendResult, sentMessage) = await admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'Reaction retry target',
        );
        expect(sendResult, SendGroupMessageResult.success);
        expect(sentMessage, isNotNull);

        await pump();
        final readerMessages = await reader.loadGroupMessages(groupId);
        final delivered = readerMessages.firstWhere(
          (message) => message.id == sentMessage!.id,
        );

        network.unsubscribe(groupId, reader.peerId);
        adminBridge.inboxStoreFailuresRemaining = 2;

        final (addResult, addReaction) = await group_react.sendGroupReaction(
          bridge: admin.bridge,
          groupRepo: admin.groupRepo,
          msgRepo: admin.msgRepo,
          reactionRepo: admin.reactionRepo!,
          reactionReplayOutboxRepo: admin.reactionReplayOutboxRepo,
          groupId: groupId,
          messageId: delivered.id,
          emoji: '🔥',
          senderPeerId: admin.peerId,
          senderPublicKey: admin.publicKey,
          senderPrivateKey: admin.privateKey,
        );
        expect(addResult, group_react.SendGroupReactionResult.success);
        expect(addReaction, isNotNull);

        final removeResult = await removeGroupReaction(
          bridge: admin.bridge,
          groupRepo: admin.groupRepo,
          reactionRepo: admin.reactionRepo!,
          reactionReplayOutboxRepo: admin.reactionReplayOutboxRepo,
          groupId: groupId,
          messageId: delivered.id,
          emoji: '🔥',
          senderPeerId: admin.peerId,
          senderPublicKey: admin.publicKey,
          senderPrivateKey: admin.privateKey,
        );
        expect(removeResult, RemoveGroupReactionResult.success);

        await pump();

        final pendingEntries = await admin.reactionReplayOutboxRepo
            .loadRetryableEntries(limit: 10);
        expect(pendingEntries, hasLength(2));
        expect(
          pendingEntries.map((entry) => entry.action),
          containsAll(<String>['add', 'remove']),
        );

        final inboxStoreCountBeforeRetry = bridgePayloads(
          admin.bridge,
          'group:inboxStore',
        ).length;

        await simulateBackgroundForegroundCycle(
          bridge: admin.bridge,
          p2pService: FakeP2PService(),
          messageRepo: InMemoryMessageRepository(),
          groupMsgRepo: admin.msgRepo,
          retryFailedGroupInboxStoresFn: () => retryFailedGroupInboxStores(
            bridge: admin.bridge,
            msgRepo: admin.msgRepo,
            reactionReplayOutboxRepo: admin.reactionReplayOutboxRepo,
          ),
        );

        final retriedInboxStores = bridgePayloads(
          admin.bridge,
          'group:inboxStore',
        ).skip(inboxStoreCountBeforeRetry).toList(growable: false);
        expect(retriedInboxStores, hasLength(2));

        readerBridge.addPage(groupId, '', [
          {
            'from': admin.peerId,
            'message': retriedInboxStores[0]['message'] as String,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
          {
            'from': admin.peerId,
            'message': retriedInboxStores[1]['message'] as String,
            'timestamp': DateTime.now().millisecondsSinceEpoch + 1,
          },
        ], '');

        await drainGroupOfflineInbox(
          bridge: reader.bridge,
          groupRepo: reader.groupRepo,
          msgRepo: reader.msgRepo,
          reactionRepo: reader.reactionRepo,
        );

        final recoveredReactions = await reader.reactionRepo!
            .getReactionsForMessage(delivered.id);
        expect(
          recoveredReactions,
          isEmpty,
          reason: 'offline reader should converge to the final removed state',
        );

        final retryableAfterResume = await admin.reactionReplayOutboxRepo
            .loadRetryableEntries(limit: 10);
        expect(retryableAfterResume, isEmpty);
      },
    );

    test(
      'removed offline member drains replayed removal, loses group access, and cannot send after resume',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-offline-remove-peer',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-offline-remove-peer',
          username: 'Bob',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-offline-remove-peer',
          username: 'Charlie',
          network: network,
        );
        final bobBridge = bob.bridge as _CursorInboxBridge;

        const groupId = 'group-offline-member-removed';
        final joinedAt = DateTime.now().toUtc();

        await admin.createGroup(groupId: groupId, name: 'Offline Removal');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);

        Future<void> saveKey(GroupTestUser user) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: 'test-key',
              createdAt: joinedAt,
            ),
          );
        }

        await saveKey(admin);
        await saveKey(bob);
        await saveKey(charlie);

        admin.start();
        bob.start();
        charlie.start();

        final removedGroups = <String>[];
        final removedSub = bob.groupMessageListener.groupRemovedStream.listen(
          removedGroups.add,
        );

        network.unsubscribe(groupId, bob.peerId);

        await admin.removeMember(
          groupId: groupId,
          memberPeerId: bob.peerId,
          memberUsername: 'Bob',
        );
        await pump();

        expect(await bob.groupRepo.getGroup(groupId), isNotNull);
        expect(removedGroups, isEmpty);

        final group = await admin.groupRepo.getGroup(groupId);
        final remainingMembers = await admin.groupRepo.getMembers(groupId);
        final removalSystemMessage = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': bob.peerId, 'username': 'Bob'},
          'groupConfig': {
            'name': group!.name,
            'groupType': group.type.toValue(),
            if (group.description != null) 'description': group.description,
            'members': remainingMembers
                .map(
                  (member) => {
                    'peerId': member.peerId,
                    'username': member.username,
                    'role': member.role.toValue(),
                    'publicKey': member.publicKey,
                  },
                )
                .toList(),
            'createdBy': group.createdBy,
            'createdAt': group.createdAt.toUtc().toIso8601String(),
          },
        });

        await storeGroupOfflineReplayEnvelope(
          bridge: admin.bridge,
          groupRepo: admin.groupRepo,
          groupId: groupId,
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintext: jsonEncode({
            'groupId': groupId,
            'senderId': admin.peerId,
            'senderUsername': admin.username,
            'keyEpoch': 0,
            'text': removalSystemMessage,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          }),
          keyInfo: GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-key',
            createdAt: joinedAt,
          ),
          senderPeerId: admin.peerId,
          senderPublicKey: admin.publicKey,
          senderPrivateKey: admin.privateKey,
          recipientPeerIds: [bob.peerId],
        );

        _injectInboxMessageFromLatestStore(
          senderBridge: admin.bridge,
          receiverBridge: bobBridge,
          receiverPeerId: bob.peerId,
          groupId: groupId,
        );

        await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          groupMessageListener: bob.groupMessageListener,
        );

        expect(removedGroups, contains(groupId));
        expect(await bob.groupRepo.getGroup(groupId), isNull);
        expect(bob.bridge.commandLog, contains('group:leave'));
        expect(await bob.loadGroupMessages(groupId), isEmpty);

        final (result, message) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'Should not send after offline removal',
        );

        expect(result, SendGroupMessageResult.groupNotFound);
        expect(message, isNull);
        expect(
          bob.bridge.commandLog.where((command) => command == 'group:publish'),
          isEmpty,
        );

        await removedSub.cancel();
        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'removed offline member does not retry queued failed sends after replayed removal',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-offline-remove-retry-peer',
          username: 'Admin',
          network: network,
        );
        final bobBridge = _CursorInboxBridge();
        final bob = GroupTestUser.create(
          peerId: 'bob-offline-remove-retry-peer',
          username: 'Bob',
          network: network,
          bridge: bobBridge,
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-offline-remove-retry-peer',
          username: 'Charlie',
          network: network,
        );

        const groupId = 'group-offline-remove-retry';
        await admin.createGroup(groupId: groupId, name: 'Offline Retry Block');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);
        await _saveKey(admin, groupId, 1, 'k1');
        await _saveKey(bob, groupId, 1, 'k1');
        await _saveKey(charlie, groupId, 1, 'k1');

        admin.start();
        bob.start();
        charlie.start();

        network.unsubscribe(groupId, bob.peerId);
        bobBridge.responses['group:publish'] = {
          'ok': false,
          'errorCode': 'OFFLINE',
        };
        bobBridge.responses['group:inboxStore'] = {
          'ok': false,
          'errorCode': 'OFFLINE',
        };

        final (queuedResult, queuedMessage) = await sendGroupMessage(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          groupId: groupId,
          text: 'Queued before remote removal',
          senderPeerId: bob.peerId,
          senderPublicKey: bob.publicKey,
          senderPrivateKey: bob.privateKey,
          senderUsername: bob.username,
        );

        expect(queuedResult, SendGroupMessageResult.error);
        expect(queuedMessage, isNotNull);
        expect(queuedMessage!.status, 'failed');
        expect(
          bobBridge.commandLog.where((command) => command == 'group:publish'),
          hasLength(1),
        );
        expect(
          bobBridge.commandLog.where(
            (command) => command == 'group:inboxStore',
          ),
          hasLength(1),
        );

        final removedGroups = <String>[];
        final removedSub = bob.groupMessageListener.groupRemovedStream.listen(
          removedGroups.add,
        );

        await admin.removeMember(
          groupId: groupId,
          memberPeerId: bob.peerId,
          memberUsername: 'Bob',
        );
        await _saveKey(admin, groupId, 2, 'k2');
        await _saveKey(charlie, groupId, 2, 'k2');
        await pump();

        final group = await admin.groupRepo.getGroup(groupId);
        final remainingMembers = await admin.groupRepo.getMembers(groupId);
        final removalSystemMessage = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': bob.peerId, 'username': 'Bob'},
          'groupConfig': {
            'name': group!.name,
            'groupType': group.type.toValue(),
            if (group.description != null) 'description': group.description,
            'members': remainingMembers
                .map(
                  (member) => {
                    'peerId': member.peerId,
                    'username': member.username,
                    'role': member.role.toValue(),
                    'publicKey': member.publicKey,
                  },
                )
                .toList(),
            'createdBy': group.createdBy,
            'createdAt': group.createdAt.toUtc().toIso8601String(),
          },
        });

        await storeGroupOfflineReplayEnvelope(
          bridge: admin.bridge,
          groupRepo: admin.groupRepo,
          groupId: groupId,
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintext: jsonEncode({
            'groupId': groupId,
            'senderId': admin.peerId,
            'senderUsername': admin.username,
            'keyEpoch': 0,
            'text': removalSystemMessage,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          }),
          keyInfo: GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'k1',
            createdAt: DateTime.now().toUtc(),
          ),
          senderPeerId: admin.peerId,
          senderPublicKey: admin.publicKey,
          senderPrivateKey: admin.privateKey,
          recipientPeerIds: [bob.peerId],
        );

        _injectInboxMessageFromLatestStore(
          senderBridge: admin.bridge,
          receiverBridge: bobBridge,
          receiverPeerId: bob.peerId,
          groupId: groupId,
        );

        await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          groupMessageListener: bob.groupMessageListener,
        );

        expect(removedGroups, contains(groupId));
        expect(await bob.groupRepo.getGroup(groupId), isNotNull);
        expect(await bob.groupRepo.getMember(groupId, bob.peerId), isNull);
        expect(await bob.groupRepo.getLatestKey(groupId), isNull);
        expect(bobBridge.commandLog, contains('group:leave'));

        final publishCountBeforeRetry = bobBridge.commandLog
            .where((command) => command == 'group:publish')
            .length;
        final inboxStoreCountBeforeRetry = bobBridge.commandLog
            .where((command) => command == 'group:inboxStore')
            .length;

        final retried = await retryFailedGroupMessages(
          groupMsgRepo: bob.msgRepo,
          groupRepo: bob.groupRepo,
          identityRepo: _Section10IdentityRepository(_identityForUser(bob)),
          bridge: bob.bridge,
          mediaAttachmentRepo: bob.mediaAttachmentRepo,
        );

        expect(retried, 0);
        expect(
          bobBridge.commandLog.where((command) => command == 'group:publish'),
          hasLength(publishCountBeforeRetry),
        );
        expect(
          bobBridge.commandLog.where(
            (command) => command == 'group:inboxStore',
          ),
          hasLength(inboxStoreCountBeforeRetry),
        );

        final staleQueued = await bob.msgRepo.getMessage(queuedMessage.id);
        expect(staleQueued, isNotNull);
        expect(staleQueued!.status, 'failed');

        await removedSub.cancel();
        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'offline remaining member drains remove-vs-send backlog and keeps the same before-cutoff outcome after resume',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-offline-remaining-peer',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-offline-remaining-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-offline-remaining-peer',
          username: 'Charlie',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final charlieBridge = charlie.bridge as _CursorInboxBridge;

        const groupId = 'group-offline-remaining-cutoff';
        final joinedAt = DateTime.now().toUtc();

        await admin.createGroup(groupId: groupId, name: 'Offline Remaining');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);

        Future<void> saveKey(GroupTestUser user) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: 'test-key',
              createdAt: joinedAt,
            ),
          );
        }

        await saveKey(admin);
        await saveKey(bob);
        await saveKey(charlie);

        admin.start();
        bob.start();
        charlie.start();

        network.unsubscribe(groupId, charlie.peerId);

        await admin.removeMember(
          groupId: groupId,
          memberPeerId: bob.peerId,
          memberUsername: 'Bob',
        );
        await pump();

        expect(
          await charlie.groupRepo.getMember(groupId, bob.peerId),
          isNotNull,
        );

        final adminMessages = await admin.loadGroupMessages(groupId);
        final removalEntry = adminMessages.firstWhere(
          (message) => message.id.startsWith(
            'sys-member_removed:$groupId:${bob.peerId}:',
          ),
        );
        final removedAt = removalEntry.timestamp.toUtc();

        final group = await admin.groupRepo.getGroup(groupId);
        final remainingMembers = await admin.groupRepo.getMembers(groupId);
        final removalSystemMessage = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': bob.peerId, 'username': 'Bob'},
          'removedAt': removedAt.toIso8601String(),
          'groupConfig': {
            'name': group!.name,
            'groupType': group.type.toValue(),
            if (group.description != null) 'description': group.description,
            'members': remainingMembers
                .map(
                  (member) => {
                    'peerId': member.peerId,
                    'username': member.username,
                    'role': member.role.toValue(),
                    'publicKey': member.publicKey,
                  },
                )
                .toList(),
            'createdBy': group.createdBy,
            'createdAt': group.createdAt.toUtc().toIso8601String(),
          },
        });

        charlieBridge.addPage(groupId, '', [
          await _signedReplayRelayMessage(
            bridge: charlie.bridge,
            groupRepo: charlie.groupRepo,
            groupId: groupId,
            payload: {
              'groupId': groupId,
              'senderId': bob.peerId,
              'senderUsername': 'Bob',
              'keyEpoch': 1,
              'text': 'Before cutoff replay',
              'timestamp': removedAt
                  .subtract(const Duration(milliseconds: 1))
                  .toIso8601String(),
              'messageId': 'msg-before-cutoff-replay',
            },
            senderPeerId: bob.peerId,
            senderPublicKey: bob.publicKey,
            senderPrivateKey: bob.privateKey,
          ),
          await _signedReplayRelayMessage(
            bridge: admin.bridge,
            groupRepo: admin.groupRepo,
            groupId: groupId,
            payload: {
              'groupId': groupId,
              'senderId': admin.peerId,
              'senderUsername': admin.username,
              'keyEpoch': 0,
              'text': removalSystemMessage,
              'timestamp': removedAt.toIso8601String(),
              'messageId': 'msg-remove-bob-replay',
            },
            senderPeerId: admin.peerId,
            senderPublicKey: admin.publicKey,
            senderPrivateKey: admin.privateKey,
          ),
        ], '');

        await rejoinGroupTopics(
          bridge: charlie.bridge,
          groupRepo: charlie.groupRepo,
          reason: RejoinReason.startup,
        );
        network.subscribe(groupId, charlie.peerId);
        await drainGroupOfflineInbox(
          bridge: charlie.bridge,
          groupRepo: charlie.groupRepo,
          msgRepo: charlie.msgRepo,
          groupMessageListener: charlie.groupMessageListener,
        );

        expect(await charlie.groupRepo.getMember(groupId, bob.peerId), isNull);

        final charlieMessages = await charlie.loadGroupMessages(groupId);
        expect(
          charlieMessages.where(
            (message) => message.text == 'Before cutoff replay',
          ),
          hasLength(1),
        );
        expect(
          charlieMessages.where(
            (message) => message.text == 'At cutoff replay',
          ),
          isEmpty,
        );
        expect(
          charlieMessages.where(
            (message) => message.id.startsWith(
              'sys-member_removed:$groupId:${bob.peerId}:',
            ),
          ),
          hasLength(1),
        );

        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'IR-003 timestamp replay boundary drains same-ms fake-network messages once',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-ir003-boundary',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'reader-ir003-boundary',
          username: 'Bob',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final bobBridge = bob.bridge as _CursorInboxBridge;
        addTearDown(() {
          admin.dispose();
          bob.dispose();
        });

        const groupId = 'group-ir003-boundary';
        final boundary = DateTime.utc(2026, 5, 12, 12, 45);
        final boundaryMs = boundary.millisecondsSinceEpoch;
        await admin.createGroup(groupId: groupId, name: 'IR003 Boundary');
        await admin.addMember(groupId: groupId, invitee: bob);
        await bob.groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: admin.peerId,
            username: admin.username,
            role: MemberRole.admin,
            publicKey: admin.publicKey,
            joinedAt: DateTime.utc(2026, 5, 1),
          ),
        );
        await bob.groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: bob.peerId,
            username: bob.username,
            role: MemberRole.writer,
            publicKey: bob.publicKey,
            joinedAt: DateTime.utc(2026, 5, 1),
          ),
        );
        await _saveKey(admin, groupId, 1, 'k1');
        await _saveKey(bob, groupId, 1, 'k1');
        network.unsubscribe(groupId, bob.peerId);

        admin.start();
        bob.start();

        final firstBoundary =
            await _signedReplayRelayMessage(
                bridge: admin.bridge,
                groupRepo: bob.groupRepo,
                groupId: groupId,
                payload: {
                  'groupId': groupId,
                  'senderId': admin.peerId,
                  'senderUsername': admin.username,
                  'keyEpoch': 1,
                  'text': 'IR-003 boundary first',
                  'timestamp': boundary.toIso8601String(),
                  'messageId': 'ir003-boundary-first',
                },
                senderPeerId: admin.peerId,
                senderPublicKey: admin.publicKey,
                senderPrivateKey: admin.privateKey,
              )
              ..['timestamp'] = boundaryMs;
        bobBridge.addPage(groupId, '', [firstBoundary], '');

        final firstDrain = await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          selfPeerId: bob.peerId,
        );

        expect(firstDrain.isSuccessful, isTrue);
        final boundaryCursor =
            '$groupInboxSyntheticSinceCursorPrefix${boundaryMs - 1}';
        expect(await bob.msgRepo.getInboxCursor(groupId), boundaryCursor);
        expect(
          (await bob.loadGroupMessages(
            groupId,
          )).where((message) => message.id == 'ir003-boundary-first'),
          hasLength(1),
        );

        final secondBoundary =
            await _signedReplayRelayMessage(
                bridge: admin.bridge,
                groupRepo: bob.groupRepo,
                groupId: groupId,
                payload: {
                  'groupId': groupId,
                  'senderId': admin.peerId,
                  'senderUsername': admin.username,
                  'keyEpoch': 1,
                  'text': 'IR-003 same-ms boundary second',
                  'timestamp': boundary.toIso8601String(),
                  'messageId': 'ir003-boundary-second',
                },
                senderPeerId: admin.peerId,
                senderPublicKey: admin.publicKey,
                senderPrivateKey: admin.privateKey,
              )
              ..['timestamp'] = boundaryMs;
        final adjacent =
            await _signedReplayRelayMessage(
                bridge: admin.bridge,
                groupRepo: bob.groupRepo,
                groupId: groupId,
                payload: {
                  'groupId': groupId,
                  'senderId': admin.peerId,
                  'senderUsername': admin.username,
                  'keyEpoch': 1,
                  'text': 'IR-003 adjacent millisecond',
                  'timestamp': boundary
                      .add(const Duration(milliseconds: 1))
                      .toIso8601String(),
                  'messageId': 'ir003-adjacent',
                },
                senderPeerId: admin.peerId,
                senderPublicKey: admin.publicKey,
                senderPrivateKey: admin.privateKey,
              )
              ..['timestamp'] = boundaryMs + 1;
        bobBridge.addPage(groupId, boundaryCursor, [
          firstBoundary,
          secondBoundary,
          adjacent,
        ], '');

        final secondDrain = await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          selfPeerId: bob.peerId,
        );

        expect(secondDrain.isSuccessful, isTrue);
        final bobMessages = await bob.loadGroupMessages(groupId);
        expect(
          bobMessages.where((message) => message.id == 'ir003-boundary-first'),
          hasLength(1),
        );
        expect(
          bobMessages.where((message) => message.id == 'ir003-boundary-second'),
          hasLength(1),
        );
        expect(
          bobMessages.where((message) => message.id == 'ir003-adjacent'),
          hasLength(1),
        );
        expect(
          await bob.msgRepo.getInboxCursor(groupId),
          '$groupInboxSyntheticSinceCursorPrefix$boundaryMs',
        );
      },
    );

    test(
      'ST-004 clock skew fake-network replay keeps relay boundary exact',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-st004-boundary',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'reader-st004-boundary',
          username: 'Bob',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final bobBridge = bob.bridge as _CursorInboxBridge;
        addTearDown(() {
          admin.dispose();
          bob.dispose();
        });

        const groupId = 'group-st004-boundary';
        final relayBoundary = DateTime.utc(2026, 5, 16, 8, 4);
        final relayBoundaryMs = relayBoundary.millisecondsSinceEpoch;
        final futureSkew = relayBoundary.add(const Duration(minutes: 10));
        final pastSkew = relayBoundary.subtract(const Duration(minutes: 7));

        await admin.createGroup(groupId: groupId, name: 'ST004 Boundary');
        await admin.addMember(groupId: groupId, invitee: bob);
        await bob.groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: admin.peerId,
            username: admin.username,
            role: MemberRole.admin,
            publicKey: admin.publicKey,
            joinedAt: DateTime.utc(2026, 5, 1),
          ),
        );
        await bob.groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: bob.peerId,
            username: bob.username,
            role: MemberRole.writer,
            publicKey: bob.publicKey,
            joinedAt: DateTime.utc(2026, 5, 1),
          ),
        );
        await _saveKey(admin, groupId, 1, 'k1');
        await _saveKey(bob, groupId, 1, 'k1');
        network.unsubscribe(groupId, bob.peerId);

        admin.start();
        bob.start();

        final firstBoundary =
            await _signedReplayRelayMessage(
                bridge: admin.bridge,
                groupRepo: bob.groupRepo,
                groupId: groupId,
                payload: {
                  'groupId': groupId,
                  'senderId': admin.peerId,
                  'senderUsername': admin.username,
                  'keyEpoch': 1,
                  'text': 'ST-004 boundary first with future skew',
                  'timestamp': futureSkew.toIso8601String(),
                  'messageId': 'st004-boundary-first',
                },
                senderPeerId: admin.peerId,
                senderPublicKey: admin.publicKey,
                senderPrivateKey: admin.privateKey,
              )
              ..['timestamp'] = relayBoundaryMs;
        final cursorBoundary =
            await _signedReplayRelayMessage(
                bridge: admin.bridge,
                groupRepo: bob.groupRepo,
                groupId: groupId,
                payload: {
                  'groupId': groupId,
                  'senderId': admin.peerId,
                  'senderUsername': admin.username,
                  'keyEpoch': 1,
                  'text': 'ST-004 cursor page exact',
                  'timestamp': pastSkew.toIso8601String(),
                  'messageId': 'st004-cursor-page-boundary',
                },
                senderPeerId: admin.peerId,
                senderPublicKey: admin.publicKey,
                senderPrivateKey: admin.privateKey,
              )
              ..['timestamp'] = relayBoundaryMs;
        bobBridge.addPage(groupId, '', [firstBoundary], 'st004-opaque-page-2');
        bobBridge.addPage(groupId, 'st004-opaque-page-2', [cursorBoundary], '');

        final firstDrain = await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          selfPeerId: bob.peerId,
        );

        expect(firstDrain.isSuccessful, isTrue);
        final boundaryCursor =
            '$groupInboxSyntheticSinceCursorPrefix${relayBoundaryMs - 1}';
        expect(await bob.msgRepo.getInboxCursor(groupId), boundaryCursor);
        final cursorCommands = bobBridge.sentMessages
            .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
            .where((message) => message['cmd'] == 'group:inboxRetrieveCursor')
            .toList(growable: false);
        expect(cursorCommands, hasLength(2));
        expect(cursorCommands[0]['payload']['cursor'], '');
        expect(cursorCommands[1]['payload']['cursor'], 'st004-opaque-page-2');

        final secondBoundary =
            await _signedReplayRelayMessage(
                bridge: admin.bridge,
                groupRepo: bob.groupRepo,
                groupId: groupId,
                payload: {
                  'groupId': groupId,
                  'senderId': admin.peerId,
                  'senderUsername': admin.username,
                  'keyEpoch': 1,
                  'text': 'ST-004 same boundary after skew',
                  'timestamp': pastSkew.toIso8601String(),
                  'messageId': 'st004-boundary-second',
                },
                senderPeerId: admin.peerId,
                senderPublicKey: admin.publicKey,
                senderPrivateKey: admin.privateKey,
              )
              ..['timestamp'] = relayBoundaryMs;
        final adjacent =
            await _signedReplayRelayMessage(
                bridge: admin.bridge,
                groupRepo: bob.groupRepo,
                groupId: groupId,
                payload: {
                  'groupId': groupId,
                  'senderId': admin.peerId,
                  'senderUsername': admin.username,
                  'keyEpoch': 1,
                  'text': 'ST-004 adjacent millisecond after skew',
                  'timestamp': futureSkew.toIso8601String(),
                  'messageId': 'st004-boundary-adjacent',
                },
                senderPeerId: admin.peerId,
                senderPublicKey: admin.publicKey,
                senderPrivateKey: admin.privateKey,
              )
              ..['timestamp'] = relayBoundaryMs + 1;
        bobBridge.addPage(groupId, boundaryCursor, [
          firstBoundary,
          secondBoundary,
          adjacent,
        ], '');

        final secondDrain = await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          selfPeerId: bob.peerId,
        );

        expect(secondDrain.isSuccessful, isTrue);
        final bobMessages = await bob.loadGroupMessages(groupId);
        for (final messageId in const [
          'st004-boundary-first',
          'st004-cursor-page-boundary',
          'st004-boundary-second',
          'st004-boundary-adjacent',
        ]) {
          expect(
            bobMessages.where((message) => message.id == messageId),
            hasLength(1),
            reason: messageId,
          );
        }
        expect(
          await bob.msgRepo.getInboxCursor(groupId),
          '$groupInboxSyntheticSinceCursorPrefix$relayBoundaryMs',
        );
      },
    );

    test(
      'watchdog restart rejoins topics and receives subsequent live messages',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
        );

        const groupId = 'group-watchdog-1';
        await alice.createGroup(groupId: groupId, name: 'Watchdog Test');
        await alice.addMember(groupId: groupId, invitee: bob);

        await bob.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        alice.start();
        bob.start();

        // Normal messaging works.
        await alice.sendGroupMessage(groupId: groupId, text: 'Before watchdog');
        await pump();
        var bobMessages = await bob.loadGroupMessages(groupId);
        expect(bobMessages.where((m) => m.isIncoming), hasLength(1));

        // Simulate watchdog restart: unsubscribe Bob (Go node restarted).
        network.unsubscribe(groupId, bob.peerId);

        // Rejoin with watchdog restart reason.
        await rejoinGroupTopics(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          reason: RejoinReason.watchdogRestart,
        );

        // Verify bridge received join command.
        final joinCmds = bob.bridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .where((m) => m['cmd'] == 'group:join')
            .toList();
        expect(joinCmds, isNotEmpty);

        // Re-subscribe on fake network (in production, Go does this internally).
        network.subscribe(groupId, bob.peerId);

        // Live messages should work after rejoin.
        await alice.sendGroupMessage(
          groupId: groupId,
          text: 'After watchdog restart',
        );
        await pump();
        bobMessages = await bob.loadGroupMessages(groupId);
        expect(bobMessages.where((m) => m.isIncoming), hasLength(2));

        alice.dispose();
        bob.dispose();
      },
    );

    test(
      'announcement reader backgrounded during send receives missed announces after resume',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-peer',
          username: 'Admin',
          network: network,
        );
        final reader = GroupTestUser.create(
          peerId: 'reader-peer',
          username: 'Reader',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final onlineReader = GroupTestUser.create(
          peerId: 'online-reader-peer',
          username: 'OnlineReader',
          network: network,
        );
        final readerBridge = reader.bridge as _CursorInboxBridge;
        final p2pService = FakeP2PService();
        final lifecycleMessageRepo = InMemoryMessageRepository();
        SendGroupMessageResult? sendResult;
        GroupMessage? sent;

        const groupId = 'group-announce-resume';
        await admin.createGroup(
          groupId: groupId,
          name: 'Announcements',
          type: GroupType.announcement,
        );
        await admin.addMember(groupId: groupId, invitee: reader);
        await admin.addMember(groupId: groupId, invitee: onlineReader);

        await _saveKey(admin, groupId, 1, 'test-key');
        await _saveKey(reader, groupId, 1, 'test-key');
        await _saveKey(onlineReader, groupId, 1, 'test-key');

        admin.start();
        reader.start();
        onlineReader.start();

        await simulateBackgroundForegroundCycle(
          bridge: reader.bridge,
          p2pService: p2pService,
          messageRepo: lifecycleMessageRepo,
          groupMsgRepo: reader.msgRepo,
          afterPause: () async {
            network.unsubscribe(groupId, reader.peerId);
            (sendResult, sent) = await admin.sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'Announcement 2',
            );
            _injectInboxMessageFromLatestStore(
              senderBridge: admin.bridge,
              receiverBridge: readerBridge,
              receiverPeerId: reader.peerId,
              groupId: groupId,
            );
          },
          afterResume: () async {
            await drainGroupOfflineInbox(
              bridge: reader.bridge,
              groupRepo: reader.groupRepo,
              msgRepo: reader.msgRepo,
            );
            network.subscribe(groupId, reader.peerId);
          },
        );

        expect(sendResult, SendGroupMessageResult.success);
        expect(sent, isNotNull);
        expect(sent!.status, 'sent');
        expect(admin.bridge.commandLog, contains('group:publish'));
        expect(admin.bridge.commandLog, contains('group:inboxStore'));

        final onlineReaderMessages = await onlineReader.loadGroupMessages(
          groupId,
        );
        expect(
          onlineReaderMessages.any(
            (message) => message.text == 'Announcement 2',
          ),
          isTrue,
        );

        final readerMessages = await reader.loadGroupMessages(groupId);
        expect(
          readerMessages.any((message) => message.text == 'Announcement 2'),
          isTrue,
        );

        admin.dispose();
        reader.dispose();
        onlineReader.dispose();
      },
    );

    testWidgets(
      '10-A acceptance uses real GroupConversationWired sender path with reader lifecycle inbox recovery',
      (tester) async {
        await _section10WidgetTextLifecycleProof(tester, network);
      },
    );

    test(
      'announcement media send with zero topic peers stays sent and readers recover intact media refs after resume',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-media-peer',
          username: 'Admin',
          network: network,
        );
        final reader = GroupTestUser.create(
          peerId: 'reader-media-peer',
          username: 'Reader',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final readerBridge = reader.bridge as _CursorInboxBridge;
        final p2pService = FakeP2PService();
        final lifecycleMessageRepo = InMemoryMessageRepository();
        SendGroupMessageResult? sendResult;
        GroupMessage? sent;

        const groupId = 'group-announce-media-resume';
        await admin.createGroup(
          groupId: groupId,
          name: 'Announcements Media',
          type: GroupType.announcement,
        );
        await admin.addMember(groupId: groupId, invitee: reader);

        await admin.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 4,
            encryptedKey: 'k4',
            createdAt: DateTime.now().toUtc(),
          ),
        );
        await reader.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 4,
            encryptedKey: 'k4',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        admin.start();
        reader.start();

        final mediaAttachment = MediaAttachment(
          id: 'att-proof-1',
          messageId: '',
          mime: 'image/jpeg',
          size: 12,
          mediaType: 'image',
          width: 1280,
          height: 720,
          localPath: 'media/group-announce-media-resume/att-proof-1.jpg',
          downloadStatus: 'done',
          contentHash: _validContentHash,
          encryptionKeyBase64: 'key-att-proof-1',
          encryptionNonce: 'nonce-att-proof-1',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          createdAt: DateTime.now().toUtc().toIso8601String(),
        );

        await simulateBackgroundForegroundCycle(
          bridge: reader.bridge,
          p2pService: p2pService,
          messageRepo: lifecycleMessageRepo,
          groupMsgRepo: reader.msgRepo,
          afterPause: () async {
            network.unsubscribe(groupId, reader.peerId);
            (sendResult, sent) = await admin.sendGroupMessageViaBridge(
              groupId: groupId,
              text: '',
              mediaAttachments: [mediaAttachment],
              publishTopicPeersOverride: 0,
            );
            _injectInboxMessageFromLatestStore(
              senderBridge: admin.bridge,
              receiverBridge: readerBridge,
              receiverPeerId: reader.peerId,
              groupId: groupId,
            );
          },
          afterResume: () async {
            await drainGroupOfflineInbox(
              bridge: reader.bridge,
              groupRepo: reader.groupRepo,
              msgRepo: reader.msgRepo,
              mediaAttachmentRepo: reader.mediaAttachmentRepo,
            );
            network.subscribe(groupId, reader.peerId);
          },
        );

        expect(sendResult, SendGroupMessageResult.successNoPeers);
        expect(sent, isNotNull);
        expect(sent!.status, 'sent');
        expect(sent!.keyGeneration, 4);

        final readerMessages = await reader.loadGroupMessages(groupId);
        final delivered = readerMessages.firstWhere(
          (message) => message.id == sent!.id,
        );
        expect(delivered.keyGeneration, 4);

        final deliveredMedia = await reader.mediaAttachmentRepo
            .getAttachmentsForMessage(delivered.id);
        expect(deliveredMedia, hasLength(1));
        expect(deliveredMedia.single.id, 'att-proof-1');
        expect(deliveredMedia.single.mediaType, 'image');
        expect(deliveredMedia.single.width, 1280);
        expect(deliveredMedia.single.height, 720);

        admin.dispose();
        reader.dispose();
      },
    );

    testWidgets(
      '10-B acceptance uses real GroupConversationWired sender path for media + resume fallback',
      (tester) async {
        await _section10WidgetMediaLifecycleProof(tester, network);
      },
    );

    testWidgets(
      '10-C acceptance uses real GroupConversationWired sender path for voice + no plaintext push body',
      (tester) async {
        await _section10WidgetVoiceLifecycleProof(tester, network);
      },
    );

    test(
      'announcement admin send after key rotation uses the new epoch and remains deliverable',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-rot-peer',
          username: 'Admin',
          network: network,
        );
        final reader = GroupTestUser.create(
          peerId: 'reader-rot-peer',
          username: 'Reader',
          network: network,
        );

        const groupId = 'group-announce-rotation';
        await admin.createGroup(
          groupId: groupId,
          name: 'Announcements Rotation',
          type: GroupType.announcement,
        );
        await admin.addMember(groupId: groupId, invitee: reader);

        await admin.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'k1',
            createdAt: DateTime.now().toUtc(),
          ),
        );
        await reader.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'k1',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        admin.start();
        reader.start();

        await admin.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 2,
            encryptedKey: 'k2',
            createdAt: DateTime.now().toUtc(),
          ),
        );
        await reader.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 2,
            encryptedKey: 'k2',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        final (result, sent) = await admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'After rotation',
        );
        expect(result, SendGroupMessageResult.success);
        expect(sent, isNotNull);
        expect(sent!.keyGeneration, 2);
        expect(sent.status, 'sent');
        expect(admin.bridge.commandLog, contains('group:publish'));
        expect(admin.bridge.commandLog, contains('group:inboxStore'));

        await pump();
        final readerMessages = await reader.loadGroupMessages(groupId);
        final incomingAfterRotation = readerMessages.firstWhere(
          (message) => message.isIncoming && message.text == 'After rotation',
        );
        expect(incomingAfterRotation.keyGeneration, 2);

        admin.dispose();
        reader.dispose();
      },
    );

    testWidgets(
      '10-F acceptance uses real GroupConversationWired sender path after key rotation',
      (tester) async {
        await _section10WidgetRotationLifecycleProof(tester, network);
      },
    );

    testWidgets(
      'MM-012 acceptance uses real GroupConversationWired sender path to keep discussion sendable and announcement admin blocked during active recovery',
      (tester) async {
        addTearDown(groupRecoveryGate.resetForTest);

        Future<void> expectDiscussionAllowed({
          required String groupId,
          required String name,
          required String draftText,
        }) async {
          final sender = GroupTestUser.create(
            peerId: '$groupId-peer',
            username: 'Alice',
            network: network,
          );
          addTearDown(sender.dispose);

          await sender.createGroup(
            groupId: groupId,
            name: name,
            type: GroupType.chat,
          );
          await _saveKey(sender, groupId, 1, 'k1');

          await _pumpSection10SenderWidget(
            tester,
            sender: sender,
            groupId: groupId,
            bridge: sender.bridge,
          );

          groupRecoveryGate.begin();
          try {
            await _sendText(tester, draftText);
            await _pumpFrames(tester, count: 20);
          } finally {
            groupRecoveryGate.end();
          }

          expect(
            sender.bridge.commandLog.where((cmd) => cmd == 'group:publish'),
            hasLength(1),
          );
          expect(
            sender.bridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
            hasLength(1),
          );
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller?.text,
            isEmpty,
          );
          expect(find.text(draftText), findsOneWidget);
          expect(
            (await sender.msgRepo.getMessagesPage(groupId, limit: 20)).where(
              (message) => !message.isIncoming && message.text == draftText,
            ),
            hasLength(1),
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }

        Future<void> expectAnnouncementBlocked({
          required String groupId,
          required String name,
          required String draftText,
        }) async {
          final sender = GroupTestUser.create(
            peerId: '$groupId-peer',
            username: 'Alice',
            network: network,
          );
          addTearDown(sender.dispose);

          await sender.createGroup(
            groupId: groupId,
            name: name,
            type: GroupType.announcement,
          );
          await _saveKey(sender, groupId, 1, 'k1');

          await _pumpSection10SenderWidget(
            tester,
            sender: sender,
            groupId: groupId,
            bridge: sender.bridge,
          );

          groupRecoveryGate.begin();
          try {
            await _sendText(tester, draftText);
            await _pumpFrames(tester, count: 20);
          } finally {
            groupRecoveryGate.end();
          }

          expect(
            sender.bridge.commandLog.where((cmd) => cmd == 'group:publish'),
            isEmpty,
          );
          expect(
            sender.bridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
            isEmpty,
          );
          expect(find.text(draftText), findsOneWidget);
          expect(
            (await sender.msgRepo.getMessagesPage(groupId, limit: 20)).where(
              (message) => !message.isIncoming && message.text == draftText,
            ),
            isEmpty,
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }

        await expectDiscussionAllowed(
          groupId: 'group-recovery-send-chat',
          name: 'Recovery Chat',
          draftText: 'Discussion recovery send',
        );
        await expectAnnouncementBlocked(
          groupId: 'group-recovery-send-announce',
          name: 'Recovery Announcement',
          draftText: 'Announcement recovery block',
        );
      },
    );

    test(
      'group discovery remains live across ttl refresh window without manual rejoin',
      () async {
        // This is a structural test: verify that after rejoining,
        // the topic subscription persists without needing manual re-rejoin.
        final alice = GroupTestUser.create(
          peerId: 'alice-peer',
          username: 'Alice',
          network: network,
        );

        const groupId = 'group-ttl-refresh';
        await alice.createGroup(groupId: groupId, name: 'TTL Test');

        await alice.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        alice.start();

        // Verify subscription is active.
        expect(network.isSubscribed(groupId, alice.peerId), isTrue);

        // Simulate time passing (no manual rejoin needed).
        await pump();

        // Subscription should still be active.
        expect(network.isSubscribed(groupId, alice.peerId), isTrue);

        alice.dispose();
      },
    );

    test(
      'fake group network delivers live messages without explicit relay simulation',
      () async {
        // Structural fake-network coverage only. Real Go dial policy is
        // asserted in go-mknoon/node tests against live libp2p hosts.
        final alice = GroupTestUser.create(
          peerId: 'alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
        );

        const groupId = 'group-direct-path';
        await alice.createGroup(groupId: groupId, name: 'Direct Test');
        await alice.addMember(groupId: groupId, invitee: bob);

        alice.start();
        bob.start();

        // Message delivery works directly (no relay setup needed in tests).
        await alice.sendGroupMessage(groupId: groupId, text: 'Direct msg');
        await pump();

        final bobMessages = await bob.loadGroupMessages(groupId);
        expect(bobMessages.where((m) => m.isIncoming), hasLength(1));

        alice.dispose();
        bob.dispose();
      },
    );

    test(
      'many joined groups resume without bursting recovery work all at once',
      () async {
        final user = GroupTestUser.create(
          peerId: 'user-peer',
          username: 'User',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final userBridge = user.bridge as _CursorInboxBridge;

        // Create 5 groups.
        final groupIds = List.generate(5, (i) => 'group-multi-$i');
        for (final gid in groupIds) {
          await user.createGroup(groupId: gid, name: 'Multi $gid');
          await _saveLegacyBacklogSender(
            user,
            groupId: gid,
            peerId: 'other-peer',
            username: 'Other',
          );
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: gid,
              keyGeneration: 1,
              encryptedKey: 'key-$gid',
              createdAt: DateTime.now().toUtc(),
            ),
          );

          // Each group has one offline message.
          final ts = DateTime.now().toUtc().toIso8601String();
          userBridge.addPage(gid, '', [
            await _signedReplayRelayMessage(
              bridge: user.bridge,
              groupRepo: user.groupRepo,
              groupId: gid,
              payload: {
                'groupId': gid,
                'senderId': 'other-peer',
                'senderUsername': 'Other',
                'keyEpoch': 0,
                'text': 'Missed msg in $gid',
                'timestamp': ts,
                'messageId': 'msg-multi-$gid',
              },
              senderPeerId: 'other-peer',
              senderPublicKey: 'other-peer-pk',
              senderPrivateKey: 'other-peer-sk',
            ),
          ], '');
        }

        user.start();

        // Drain all groups' inboxes.
        await drainGroupOfflineInbox(
          bridge: user.bridge,
          groupRepo: user.groupRepo,
          msgRepo: user.msgRepo,
        );

        // All 5 groups should have been drained.
        final retrieveCount = userBridge.commandLog
            .where((c) => c == 'group:inboxRetrieveCursor')
            .length;
        expect(retrieveCount, 5);

        // Verify each group has 1 message.
        for (final gid in groupIds) {
          final msgs = await user.msgRepo.getMessagesPage(gid);
          expect(
            msgs.length,
            1,
            reason: 'Group $gid should have 1 drained message',
          );
        }

        user.dispose();
      },
    );

    // =========================================================================
    // Phase 6: Multi-page cursor and watchdog restart tests
    // =========================================================================

    test(
      'resume drains missed group backlog exactly once across pages',
      () async {
        final user = GroupTestUser.create(
          peerId: 'user-peer',
          username: 'User',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final userBridge = user.bridge as _CursorInboxBridge;

        const groupId = 'group-multipage';
        await user.createGroup(groupId: groupId, name: 'Multi Page');
        await _saveLegacyBacklogSender(
          user,
          groupId: groupId,
          peerId: 'alice-peer',
          username: 'Alice',
        );
        await _saveLegacyBacklogSender(
          user,
          groupId: groupId,
          peerId: 'bob-peer',
          username: 'Bob',
        );
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        final ts = DateTime.now().toUtc().toIso8601String();

        // Page 1: 2 messages, cursor points to page 2
        userBridge.addPage(groupId, '', [
          await _signedReplayRelayMessage(
            bridge: user.bridge,
            groupRepo: user.groupRepo,
            groupId: groupId,
            payload: {
              'groupId': groupId,
              'senderId': 'alice-peer',
              'senderUsername': 'Alice',
              'keyEpoch': 0,
              'text': 'Message 1',
              'timestamp': ts,
              'messageId': 'msg-page1-1',
            },
            senderPeerId: 'alice-peer',
            senderPublicKey: 'alice-peer-pk',
            senderPrivateKey: 'alice-peer-sk',
          ),
          await _signedReplayRelayMessage(
            bridge: user.bridge,
            groupRepo: user.groupRepo,
            groupId: groupId,
            payload: {
              'groupId': groupId,
              'senderId': 'bob-peer',
              'senderUsername': 'Bob',
              'keyEpoch': 0,
              'text': 'Message 2',
              'timestamp': ts,
              'messageId': 'msg-page1-2',
            },
            senderPeerId: 'bob-peer',
            senderPublicKey: 'bob-peer-pk',
            senderPrivateKey: 'bob-peer-sk',
          ),
        ], 'cursor-page-2');

        // Page 2: 1 message, no more pages
        userBridge.addPage(groupId, 'cursor-page-2', [
          await _signedReplayRelayMessage(
            bridge: user.bridge,
            groupRepo: user.groupRepo,
            groupId: groupId,
            payload: {
              'groupId': groupId,
              'senderId': 'alice-peer',
              'senderUsername': 'Alice',
              'keyEpoch': 0,
              'text': 'Message 3',
              'timestamp': ts,
              'messageId': 'msg-page2-1',
            },
            senderPeerId: 'alice-peer',
            senderPublicKey: 'alice-peer-pk',
            senderPrivateKey: 'alice-peer-sk',
          ),
        ], '');

        user.start();

        await drainGroupOfflineInbox(
          bridge: user.bridge,
          groupRepo: user.groupRepo,
          msgRepo: user.msgRepo,
        );

        // All 3 messages from both pages should be saved
        final msgs = await user.msgRepo.getMessagesPage(groupId);
        expect(
          msgs.length,
          3,
          reason: 'All messages from both pages should be saved',
        );

        // Verify cursor commands: first page with cursor="" and second with cursor="cursor-page-2"
        final cursorCmds = userBridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .where((m) => m['cmd'] == 'group:inboxRetrieveCursor')
            .toList();
        expect(cursorCmds.length, 2, reason: 'Should have fetched 2 pages');
        expect(cursorCmds[0]['payload']['cursor'], '');
        expect(cursorCmds[1]['payload']['cursor'], 'cursor-page-2');

        user.dispose();
      },
    );

    test(
      'multi page backlog uses cursor continuation without duplication',
      () async {
        final user = GroupTestUser.create(
          peerId: 'user-peer',
          username: 'User',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final userBridge = user.bridge as _CursorInboxBridge;

        const groupId = 'group-nodup';
        await user.createGroup(groupId: groupId, name: 'No Dup');
        await _saveLegacyBacklogSender(
          user,
          groupId: groupId,
          peerId: 'alice-peer',
          username: 'Alice',
        );
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        final ts = DateTime.now().toUtc().toIso8601String();
        const sharedMsgId = 'msg-shared-id';

        // Same message on both pages (cursor should prevent this, but test the handler dedup)
        userBridge.addPage(groupId, '', [
          await _signedReplayRelayMessage(
            bridge: user.bridge,
            groupRepo: user.groupRepo,
            groupId: groupId,
            payload: {
              'groupId': groupId,
              'senderId': 'alice-peer',
              'senderUsername': 'Alice',
              'keyEpoch': 0,
              'text': 'Same message',
              'timestamp': ts,
              'messageId': sharedMsgId,
            },
            senderPeerId: 'alice-peer',
            senderPublicKey: 'alice-peer-pk',
            senderPrivateKey: 'alice-peer-sk',
          ),
        ], 'cursor-2');

        userBridge.addPage(groupId, 'cursor-2', [
          await _signedReplayRelayMessage(
            bridge: user.bridge,
            groupRepo: user.groupRepo,
            groupId: groupId,
            payload: {
              'groupId': groupId,
              'senderId': 'alice-peer',
              'senderUsername': 'Alice',
              'keyEpoch': 0,
              'text': 'Same message',
              'timestamp': ts,
              'messageId': sharedMsgId,
            },
            senderPeerId: 'alice-peer',
            senderPublicKey: 'alice-peer-pk',
            senderPrivateKey: 'alice-peer-sk',
          ),
        ], '');

        user.start();

        await drainGroupOfflineInbox(
          bridge: user.bridge,
          groupRepo: user.groupRepo,
          msgRepo: user.msgRepo,
        );

        // Despite same messageId on both pages, should be deduplicated
        final msgs = await user.msgRepo.getMessagesPage(groupId);
        expect(
          msgs.length,
          1,
          reason: 'Duplicate messageId across pages should be deduplicated',
        );

        user.dispose();
      },
    );

    test(
      'multi page replay with a tampered timestamp still keeps one stored row',
      () async {
        final user = GroupTestUser.create(
          peerId: 'user-peer',
          username: 'User',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final userBridge = user.bridge as _CursorInboxBridge;

        const groupId = 'group-nodup-timestamp';
        const sharedMsgId = 'msg-shared-timestamp';
        // Keep the replay payload comfortably inside the retention window so
        // this test continues to exercise messageId dedupe instead of aging
        // into backlog-expiry behavior as the calendar advances.
        final originalTimestamp = DateTime.now().toUtc().subtract(
          const Duration(hours: 2),
        );
        final tamperedTimestamp = originalTimestamp.add(
          const Duration(minutes: 10),
        );

        await user.createGroup(groupId: groupId, name: 'No Dup Timestamp');
        await _saveLegacyBacklogSender(
          user,
          groupId: groupId,
          peerId: 'alice-peer',
          username: 'Alice',
        );
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-key',
            createdAt: originalTimestamp,
          ),
        );

        userBridge.addPage(groupId, '', [
          await _signedReplayRelayMessage(
            bridge: user.bridge,
            groupRepo: user.groupRepo,
            groupId: groupId,
            payload: {
              'groupId': groupId,
              'senderId': 'alice-peer',
              'senderUsername': 'Alice',
              'keyEpoch': 0,
              'text': 'Same message',
              'timestamp': originalTimestamp.toIso8601String(),
              'messageId': sharedMsgId,
            },
            senderPeerId: 'alice-peer',
            senderPublicKey: 'alice-peer-pk',
            senderPrivateKey: 'alice-peer-sk',
          ),
        ], 'cursor-2');

        userBridge.addPage(groupId, 'cursor-2', [
          await _signedReplayRelayMessage(
            bridge: user.bridge,
            groupRepo: user.groupRepo,
            groupId: groupId,
            payload: {
              'groupId': groupId,
              'senderId': 'alice-peer',
              'senderUsername': 'Alice',
              'keyEpoch': 0,
              'text': 'Same message',
              'timestamp': tamperedTimestamp.toIso8601String(),
              'messageId': sharedMsgId,
            },
            senderPeerId: 'alice-peer',
            senderPublicKey: 'alice-peer-pk',
            senderPrivateKey: 'alice-peer-sk',
          ),
        ], '');

        user.start();

        await drainGroupOfflineInbox(
          bridge: user.bridge,
          groupRepo: user.groupRepo,
          msgRepo: user.msgRepo,
        );

        final msgs = await user.msgRepo.getMessagesPage(groupId);
        expect(msgs, hasLength(1));
        expect(
          msgs.single.id,
          sharedMsgId,
          reason: 'Tampered replay must not materialize a second row',
        );
        expect(
          msgs.single.timestamp,
          originalTimestamp,
          reason: 'Replay must not rewrite the accepted timestamp ordering',
        );

        user.dispose();
      },
    );

    test(
      'IR-016 long-offline mixed-window recovery keeps retained backlog and explicit cutoff state',
      () async {
        final user = GroupTestUser.create(
          peerId: 'user-peer',
          username: 'User',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final userBridge = user.bridge as _CursorInboxBridge;

        const groupId = 'group-retention-mixed-window';
        await user.createGroup(groupId: groupId, name: 'Retention Window');
        await _saveLegacyBacklogSender(
          user,
          groupId: groupId,
          peerId: 'alice-peer',
          username: 'Alice',
        );
        final historicalJoinedAt = groupBacklogRetentionCutoff(
          DateTime.now().toUtc(),
        ).subtract(const Duration(days: 1));
        final retentionGroup = await user.groupRepo.getGroup(groupId);
        await user.groupRepo.updateGroup(
          retentionGroup!.copyWith(createdAt: historicalJoinedAt),
        );
        final aliceMember = await user.groupRepo.getMember(
          groupId,
          'alice-peer',
        );
        await user.groupRepo.saveMember(
          aliceMember!.copyWith(joinedAt: historicalJoinedAt),
        );
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        final cutoff = groupBacklogRetentionCutoff(DateTime.now().toUtc());
        final expiredAt = cutoff.subtract(const Duration(hours: 1));
        final retainedAt = cutoff.add(const Duration(hours: 1));

        userBridge.addPage(groupId, '', [
          await _signedReplayRelayMessage(
            bridge: user.bridge,
            groupRepo: user.groupRepo,
            groupId: groupId,
            payload: {
              'groupId': groupId,
              'senderId': 'alice-peer',
              'senderUsername': 'Alice',
              'keyEpoch': 0,
              'text': 'Expired page',
              'timestamp': expiredAt.toIso8601String(),
              'messageId': 'msg-expired-window',
            },
            senderPeerId: 'alice-peer',
            senderPublicKey: 'alice-peer-pk',
            senderPrivateKey: 'alice-peer-sk',
          ),
        ], 'cursor-retained-window');

        userBridge.addPage(groupId, 'cursor-retained-window', [
          await _signedReplayRelayMessage(
            bridge: user.bridge,
            groupRepo: user.groupRepo,
            groupId: groupId,
            payload: {
              'groupId': groupId,
              'senderId': 'alice-peer',
              'senderUsername': 'Alice',
              'keyEpoch': 0,
              'text': 'Retained page',
              'timestamp': retainedAt.toIso8601String(),
              'messageId': 'msg-retained-window',
            },
            senderPeerId: 'alice-peer',
            senderPublicKey: 'alice-peer-pk',
            senderPrivateKey: 'alice-peer-sk',
          ),
        ], '');

        user.start();

        await drainGroupOfflineInbox(
          bridge: user.bridge,
          groupRepo: user.groupRepo,
          msgRepo: user.msgRepo,
        );
        await drainGroupOfflineInbox(
          bridge: user.bridge,
          groupRepo: user.groupRepo,
          msgRepo: user.msgRepo,
        );

        final messages = await user.msgRepo.getMessagesPage(groupId);
        final group = await user.groupRepo.getGroup(groupId);
        final cursorCmds = userBridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .where((m) => m['cmd'] == 'group:inboxRetrieveCursor')
            .toList();

        expect(messages, hasLength(1));
        expect(messages.single.id, 'msg-retained-window');
        expect(
          messages.where((message) => message.id == 'msg-expired-window'),
          isEmpty,
        );
        expect(group, isNotNull);
        expect(group!.lastBacklogExpiredAt, expiredAt);
        expect(group.lastBacklogRetainedAt, retainedAt);
        expect(
          cursorCmds,
          hasLength(3),
          reason:
              'The first drain must finish the retained cursor page, then the second drain must resume from the durable high-water cursor',
        );
        final cursors = cursorCmds
            .map((cmd) => (cmd['payload'] as Map<String, dynamic>)['cursor'])
            .cast<String>()
            .toList();
        expect(cursors[0], isEmpty);
        expect(cursors[1], 'cursor-retained-window');
        expect(cursors[2], startsWith(groupInboxSyntheticSinceCursorPrefix));
        final syntheticCursorMs = int.parse(
          cursors[2].substring(groupInboxSyntheticSinceCursorPrefix.length),
        );
        expect(
          syntheticCursorMs,
          greaterThanOrEqualTo(retainedAt.millisecondsSinceEpoch - 1),
        );

        user.dispose();
      },
    );

    test('watchdog restart rejoins topics and resumes live delivery', () async {
      final alice = GroupTestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
        bridge: _CursorInboxBridge(),
      );
      final bobBridge = bob.bridge as _CursorInboxBridge;

      const groupId = 'group-watchdog-rejoin-drain';
      await alice.createGroup(groupId: groupId, name: 'WD Rejoin');
      await alice.addMember(groupId: groupId, invitee: bob);

      await bob.groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'test-key',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      alice.start();
      bob.start();

      // Normal messaging works
      await alice.sendGroupMessage(groupId: groupId, text: 'Before WD');
      await pump();
      var msgs = await bob.loadGroupMessages(groupId);
      expect(msgs.where((m) => m.isIncoming), hasLength(1));

      // Simulate watchdog: unsubscribe Bob
      network.unsubscribe(groupId, bob.peerId);

      // Alice sends while Bob is down
      await alice.sendGroupMessage(groupId: groupId, text: 'During WD');
      await pump();

      // Bob missed the message
      msgs = await bob.loadGroupMessages(groupId);
      expect(msgs.where((m) => m.isIncoming), hasLength(1));

      // Watchdog restart: rejoin + drain inbox
      await rejoinGroupTopics(
        bridge: bob.bridge,
        groupRepo: bob.groupRepo,
        reason: RejoinReason.watchdogRestart,
      );

      final ts = DateTime.now().toUtc().toIso8601String();
      bobBridge.addPage(groupId, '', [
        await _signedReplayRelayMessage(
          bridge: alice.bridge,
          groupRepo: bob.groupRepo,
          groupId: groupId,
          payload: {
            'groupId': groupId,
            'senderId': 'alice-peer',
            'senderUsername': 'Alice',
            'keyEpoch': 0,
            'text': 'During WD',
            'timestamp': ts,
            'messageId': 'msg-wd-missed',
          },
          senderPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
        ),
      ], '');

      await drainGroupOfflineInbox(
        bridge: bob.bridge,
        groupRepo: bob.groupRepo,
        msgRepo: bob.msgRepo,
      );

      // Bob should now have 2 messages
      msgs = await bob.loadGroupMessages(groupId);
      expect(msgs.where((m) => m.isIncoming), hasLength(2));

      // Re-subscribe on network
      network.subscribe(groupId, bob.peerId);

      // New messages should work
      await alice.sendGroupMessage(groupId: groupId, text: 'After WD');
      await pump();
      msgs = await bob.loadGroupMessages(groupId);
      expect(msgs.where((m) => m.isIncoming), hasLength(3));

      alice.dispose();
      bob.dispose();
    });

    group('Section 11 test infrastructure', () {
      test('publish with zero peers falls back to inbox', () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-zero-peer',
          username: 'Alice',
          network: network,
          bridge: ZeroPeerPublishBridge(),
        );
        final bob = GroupTestUser.create(
          peerId: 'reader-zero-peer',
          username: 'Bob',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final bobBridge = bob.bridge as _CursorInboxBridge;

        const groupId = 'group-zero-peer';
        await admin.createGroup(groupId: groupId, name: 'Zero Peer Fallback');
        await admin.addMember(groupId: groupId, invitee: bob);
        await _saveKey(admin, groupId, 1, 'k1');
        await _saveKey(bob, groupId, 1, 'k1');
        network.unsubscribe(groupId, bob.peerId);

        admin.start();
        bob.start();

        final (result, sent) = await admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'Zero peers via inbox',
        );

        expect(result, SendGroupMessageResult.successNoPeers);
        expect(sent, isNotNull);
        expect(sent!.status, 'sent');
        expect(sent.inboxStored, isTrue);
        expect(admin.bridge.commandLog, contains('group:publish'));
        expect(admin.bridge.commandLog, contains('group:inboxStore'));

        _injectInboxMessageFromLatestStore(
          senderBridge: admin.bridge,
          receiverBridge: bobBridge,
          receiverPeerId: bob.peerId,
          groupId: groupId,
        );

        await drainGroupOfflineInbox(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
        );

        final bobMessages = await bob.loadGroupMessages(groupId);
        final incoming = bobMessages.where((message) => message.isIncoming);
        expect(incoming, hasLength(1));
        expect(incoming.single.text, 'Zero peers via inbox');

        admin.dispose();
        bob.dispose();
      });

      test(
        'GP-007 zero-peer send delegates to inbox without visible delay',
        () async {
          const groupId = 'group-gp007-zero-peer';
          const messageId = 'gp007-zero-peer-integration';
          const messageText = 'GP-007 zero-peer bounded integration';
          final admin = GroupTestUser.create(
            peerId: 'admin-gp007-zero-peer',
            username: 'Alice',
            network: network,
            bridge: ZeroPeerPublishBridge(),
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-gp007-zero-peer',
            username: 'Bob',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final bobBridge = bob.bridge as _CursorInboxBridge;
          addTearDown(() {
            admin.dispose();
            bob.dispose();
          });

          await admin.createGroup(groupId: groupId, name: 'GP-007 Group');
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'gp007-key');
          await _saveKey(bob, groupId, 1, 'gp007-key');
          network.unsubscribe(groupId, bob.peerId);

          admin.start();
          bob.start();

          final stopwatch = Stopwatch()..start();
          final (result, sent) = await admin.sendGroupMessageViaBridge(
            groupId: groupId,
            text: messageText,
            messageId: messageId,
          );
          stopwatch.stop();

          expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
          expect(result, SendGroupMessageResult.successNoPeers);
          expect(sent, isNotNull);
          expect(sent!.id, messageId);
          expect(sent.status, 'sent');
          expect(sent.inboxStored, isTrue);
          expect(sent.inboxRetryPayload, isNull);
          expect(admin.bridge.commandLog, contains('group:publish'));
          expect(admin.bridge.commandLog, contains('group:inboxStore'));

          final senderRow = await admin.msgRepo.getMessage(messageId);
          expect(senderRow, isNotNull);
          expect(senderRow!.status, 'sent');
          expect(senderRow.inboxStored, isTrue);
          expect(senderRow.inboxRetryPayload, isNull);

          _injectInboxMessageFromLatestStore(
            senderBridge: admin.bridge,
            receiverBridge: bobBridge,
            receiverPeerId: bob.peerId,
            groupId: groupId,
          );

          await drainGroupOfflineInbox(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            msgRepo: bob.msgRepo,
          );

          final bobMessages = await bob.loadGroupMessages(groupId);
          final incoming = bobMessages.where(
            (message) =>
                message.isIncoming &&
                message.id == messageId &&
                message.text == messageText,
          );
          expect(incoming, hasLength(1));
        },
      );

      test(
        'GI-020 zero-peer publish is repaired by later inbox replay exactly once',
        () async {
          const groupId = 'group-gi020-zero-peer-repair';
          const messageId = 'gi020-zero-peer-replay';
          const messageText = 'GI-020 zero-peer repaired by inbox replay';
          final admin = GroupTestUser.create(
            peerId: 'admin-gi020-zero-peer',
            username: 'Alice',
            network: network,
            bridge: ZeroPeerPublishBridge(),
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-gi020-zero-peer',
            username: 'Bob',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final bobBridge = bob.bridge as _CursorInboxBridge;
          addTearDown(() {
            admin.dispose();
            bob.dispose();
          });

          await admin.createGroup(groupId: groupId, name: 'GI-020 Group');
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'gi020-key');
          await _saveKey(bob, groupId, 1, 'gi020-key');
          network.unsubscribe(groupId, bob.peerId);

          admin.start();
          bob.start();

          final (result, sent) = await admin.sendGroupMessageViaBridge(
            groupId: groupId,
            text: messageText,
            messageId: messageId,
          );

          expect(result, SendGroupMessageResult.successNoPeers);
          expect(sent, isNotNull);
          expect(sent!.id, messageId);
          expect(sent.status, 'sent');
          expect(sent.inboxStored, isTrue);
          expect(sent.inboxRetryPayload, isNull);
          expect(admin.bridge.commandLog, contains('group:publish'));
          expect(admin.bridge.commandLog, contains('group:inboxStore'));

          final senderRow = await admin.msgRepo.getMessage(messageId);
          expect(senderRow, isNotNull);
          expect(senderRow!.status, 'sent');
          expect(senderRow.inboxStored, isTrue);
          expect(senderRow.inboxRetryPayload, isNull);

          var bobMessages = await bob.loadGroupMessages(groupId);
          expect(
            bobMessages.where((message) => message.id == messageId),
            isEmpty,
          );

          _injectInboxMessageFromLatestStore(
            senderBridge: admin.bridge,
            receiverBridge: bobBridge,
            receiverPeerId: bob.peerId,
            groupId: groupId,
          );

          await drainGroupOfflineInbox(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            msgRepo: bob.msgRepo,
          );

          bobMessages = await bob.loadGroupMessages(groupId);
          final incoming = bobMessages.where(
            (message) =>
                message.isIncoming &&
                message.id == messageId &&
                message.text == messageText,
          );
          expect(incoming, hasLength(1));

          await drainGroupOfflineInbox(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            msgRepo: bob.msgRepo,
          );
          bobMessages = await bob.loadGroupMessages(groupId);
          expect(
            bobMessages.where(
              (message) =>
                  message.isIncoming &&
                  message.id == messageId &&
                  message.text == messageText,
            ),
            hasLength(1),
          );

          final finalSenderRow = await admin.msgRepo.getMessage(messageId);
          expect(finalSenderRow, isNotNull);
          expect(finalSenderRow!.status, 'sent');
          expect(finalSenderRow.inboxStored, isTrue);
        },
      );

      test(
        "inbox store failure doesn't block publish but leaves sender state pending",
        () async {
          final admin = GroupTestUser.create(
            peerId: 'admin-inbox-fail-peer',
            username: 'Alice',
            network: network,
            bridge: _Section10MirroringBridge(
              network: network,
              msgRepo: InMemoryGroupMessageRepository(),
              groupRepo: InMemoryGroupRepository(),
              inboxStoreResponse: {
                'ok': false,
                'errorCode': 'INBOX_STORE_FAILED',
              },
            ),
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-inbox-fail-peer',
            username: 'Bob',
            network: network,
          );

          const groupId = 'group-inbox-fail';
          await admin.createGroup(groupId: groupId, name: 'Inbox Fail');
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');

          admin.start();
          bob.start();

          final (result, sent) = await admin.sendGroupMessageViaBridge(
            groupId: groupId,
            text: 'Publish despite inbox failure',
          );

          expect(result, SendGroupMessageResult.success);
          expect(sent, isNotNull);
          expect(sent!.status, 'pending');
          expect(sent.inboxStored, isFalse);
          expect(admin.bridge.commandLog, contains('group:publish'));
          expect(admin.bridge.commandLog, contains('group:inboxStore'));

          await pump();
          final bobMessages = await bob.loadGroupMessages(groupId);
          expect(
            bobMessages.any(
              (message) => message.text == 'Publish despite inbox failure',
            ),
            isTrue,
          );

          admin.dispose();
          bob.dispose();
        },
      );

      test(
        'zero-peer inbox failure stays owned by failed-message retry and recovers in place',
        () async {
          final adminBridge = _Section10MirroringBridge(
            network: network,
            msgRepo: InMemoryGroupMessageRepository(),
            groupRepo: InMemoryGroupRepository(),
            inboxStoreFailuresRemaining: 1,
          );
          final admin = GroupTestUser.create(
            peerId: 'admin-zero-peer-failed-retry-peer',
            username: 'Alice',
            network: network,
            bridge: adminBridge,
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-zero-peer-failed-retry-peer',
            username: 'Bob',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final bobBridge = bob.bridge as _CursorInboxBridge;

          const groupId = 'group-zero-peer-failed-retry';
          await admin.createGroup(groupId: groupId, name: 'Zero Peer Retry');
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');
          network.unsubscribe(groupId, bob.peerId);

          admin.start();
          bob.start();

          final (initialResult, initialMessage) = await admin
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: 'Zero peers need message retry',
              );

          expect(initialResult, SendGroupMessageResult.error);
          expect(initialMessage, isNotNull);
          expect(initialMessage!.status, 'failed');
          expect(initialMessage.inboxStored, isFalse);
          expect(initialMessage.inboxRetryPayload, isNotNull);
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:publish'),
            hasLength(1),
          );
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
            hasLength(1),
          );

          final inboxRetried = await retryFailedGroupInboxStores(
            bridge: admin.bridge,
            msgRepo: admin.msgRepo,
          );
          expect(inboxRetried, 0);
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
            hasLength(1),
          );

          final messageRetried = await retryFailedGroupMessages(
            groupMsgRepo: admin.msgRepo,
            groupRepo: admin.groupRepo,
            identityRepo: _Section10IdentityRepository(_identityForUser(admin)),
            bridge: admin.bridge,
            mediaAttachmentRepo: admin.mediaAttachmentRepo,
          );
          expect(messageRetried, 1);

          final recovered = await admin.msgRepo.getMessage(initialMessage.id);
          expect(recovered, isNotNull);
          expect(recovered!.id, initialMessage.id);
          expect(recovered.status, 'sent');
          expect(recovered.inboxStored, isTrue);
          expect(recovered.inboxRetryPayload, isNull);
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:publish'),
            hasLength(2),
          );
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
            hasLength(2),
          );

          _injectInboxMessageFromLatestStore(
            senderBridge: admin.bridge,
            receiverBridge: bobBridge,
            receiverPeerId: bob.peerId,
            groupId: groupId,
          );

          await drainGroupOfflineInbox(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            msgRepo: bob.msgRepo,
          );

          final bobMessages = await bob.loadGroupMessages(groupId);
          expect(
            bobMessages.where(
              (message) =>
                  message.isIncoming &&
                  message.id == initialMessage.id &&
                  message.text == 'Zero peers need message retry',
            ),
            hasLength(1),
          );

          admin.dispose();
          bob.dispose();
        },
      );

      test(
        'OB-008 fake-network degraded branches use only their retry owner',
        () async {
          final adminBridge = _Section10MirroringBridge(
            network: network,
            msgRepo: InMemoryGroupMessageRepository(),
            groupRepo: InMemoryGroupRepository(),
            inboxStoreFailuresRemaining: 1,
          );
          final admin = GroupTestUser.create(
            peerId: 'admin-ob008-retry-owner',
            username: 'Alice',
            network: network,
            bridge: adminBridge,
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-ob008-retry-owner',
            username: 'Bob',
            network: network,
          );

          const groupId = 'group-ob008-retry-owner';
          await admin.createGroup(groupId: groupId, name: 'OB-008 Owners');
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');

          admin.start();
          bob.start();

          final (pendingResult, pendingMessage) = await admin
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: 'OB-008 pending inbox owner',
              );
          expect(pendingResult, SendGroupMessageResult.success);
          expect(pendingMessage, isNotNull);
          expect(pendingMessage!.status, 'pending');
          expect(pendingMessage.inboxStored, isFalse);
          expect(pendingMessage.inboxRetryPayload, isNotNull);

          final failedMessageWrongOwner = await retryFailedGroupMessages(
            groupMsgRepo: admin.msgRepo,
            groupRepo: admin.groupRepo,
            identityRepo: _Section10IdentityRepository(_identityForUser(admin)),
            bridge: admin.bridge,
            mediaAttachmentRepo: admin.mediaAttachmentRepo,
          );
          expect(failedMessageWrongOwner, 0);
          expect(
            (await admin.msgRepo.getMessage(pendingMessage.id))!.status,
            'pending',
          );

          final inboxOwnerRetried = await retryFailedGroupInboxStores(
            bridge: admin.bridge,
            msgRepo: admin.msgRepo,
          );
          expect(inboxOwnerRetried, 1);
          final inboxRecovered = await admin.msgRepo.getMessage(
            pendingMessage.id,
          );
          expect(inboxRecovered, isNotNull);
          expect(inboxRecovered!.status, 'sent');
          expect(inboxRecovered.inboxStored, isTrue);
          expect(inboxRecovered.inboxRetryPayload, isNull);

          bob.unsubscribeFromGroup(groupId);
          adminBridge.inboxStoreFailuresRemaining = 1;
          final (failedResult, failedMessage) = await admin
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: 'OB-008 failed message owner',
              );
          expect(failedResult, SendGroupMessageResult.error);
          expect(failedMessage, isNotNull);
          expect(failedMessage!.status, 'failed');
          expect(failedMessage.inboxStored, isFalse);
          expect(failedMessage.inboxRetryPayload, isNotNull);

          final inboxWrongOwner = await retryFailedGroupInboxStores(
            bridge: admin.bridge,
            msgRepo: admin.msgRepo,
          );
          expect(inboxWrongOwner, 0);
          expect(
            (await admin.msgRepo.getMessage(failedMessage.id))!.status,
            'failed',
          );

          bob.subscribeToGroup(groupId);
          final failedMessageRetried = await retryFailedGroupMessages(
            groupMsgRepo: admin.msgRepo,
            groupRepo: admin.groupRepo,
            identityRepo: _Section10IdentityRepository(_identityForUser(admin)),
            bridge: admin.bridge,
            mediaAttachmentRepo: admin.mediaAttachmentRepo,
          );
          expect(failedMessageRetried, 1);
          final failedRecovered = await admin.msgRepo.getMessage(
            failedMessage.id,
          );
          expect(failedRecovered, isNotNull);
          expect(failedRecovered!.status, 'sent');
          expect(failedRecovered.inboxStored, isTrue);
          expect(failedRecovered.inboxRetryPayload, isNull);

          await pump();
          final bobMessages = await bob.loadGroupMessages(groupId);
          expect(
            bobMessages.where(
              (message) =>
                  message.isIncoming &&
                  message.id == failedMessage.id &&
                  message.text == 'OB-008 failed message owner',
            ),
            hasLength(1),
          );

          admin.dispose();
          bob.dispose();
        },
      );

      test(
        'IR-007 rapid pause/resume closes pending live-peer send via inbox retry exactly once',
        () async {
          final adminBridge = _Section10MirroringBridge(
            network: network,
            msgRepo: InMemoryGroupMessageRepository(),
            groupRepo: InMemoryGroupRepository(),
            inboxStoreFailuresRemaining: 1,
          );
          final admin = GroupTestUser.create(
            peerId: 'admin-rapid-pending-peer',
            username: 'Alice',
            network: network,
            bridge: adminBridge,
          );
          final liveReader = GroupTestUser.create(
            peerId: 'reader-rapid-live-peer',
            username: 'Bob',
            network: network,
          );
          final inboxReader = GroupTestUser.create(
            peerId: 'reader-rapid-inbox-peer',
            username: 'Carol',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final inboxBridge = inboxReader.bridge as _CursorInboxBridge;
          var injectedRecoveredInbox = false;

          const groupId = 'group-rapid-pending-recovery';
          await admin.createGroup(groupId: groupId, name: 'Rapid Pending');
          await admin.addMember(groupId: groupId, invitee: liveReader);
          await admin.addMember(groupId: groupId, invitee: inboxReader);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(liveReader, groupId, 1, 'k1');
          await _saveKey(inboxReader, groupId, 1, 'k1');
          network.unsubscribe(groupId, inboxReader.peerId);

          admin.start();
          liveReader.start();
          inboxReader.start();

          final (initialResult, initialMessage) = await admin
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: 'Rapid pending recovery',
              );

          expect(initialResult, SendGroupMessageResult.success);
          expect(initialMessage, isNotNull);
          expect(initialMessage!.status, 'pending');
          expect(initialMessage.inboxStored, isFalse);
          final inboxRetryRows = await admin.msgRepo
              .getMessagesWithFailedInboxStore();
          expect(inboxRetryRows.map((row) => row.id), [initialMessage.id]);
          expect(await admin.msgRepo.getFailedOutgoingMessages(), isEmpty);
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:publish'),
            hasLength(1),
          );
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
            hasLength(1),
          );

          await pump();
          final liveBeforeResume = await liveReader.loadGroupMessages(groupId);
          expect(
            liveBeforeResume.where(
              (message) => message.id == initialMessage.id,
            ),
            hasLength(1),
          );

          await simulateRapidLockUnlock(
            bridge: admin.bridge,
            p2pService: FakeP2PService(),
            messageRepo: InMemoryMessageRepository(),
            groupMsgRepo: admin.msgRepo,
            cycles: 2,
            retryFailedGroupInboxStoresFn: () async {
              final retried = await retryFailedGroupInboxStores(
                bridge: admin.bridge,
                msgRepo: admin.msgRepo,
              );
              if (retried > 0 && !injectedRecoveredInbox) {
                _injectInboxMessageFromLatestStore(
                  senderBridge: admin.bridge,
                  receiverBridge: inboxBridge,
                  receiverPeerId: inboxReader.peerId,
                  groupId: groupId,
                );
                injectedRecoveredInbox = true;
              }
              return retried;
            },
          );

          await drainGroupOfflineInbox(
            bridge: inboxReader.bridge,
            groupRepo: inboxReader.groupRepo,
            msgRepo: inboxReader.msgRepo,
          );

          final finalMessage = await _latestOutgoingMessage(
            admin.msgRepo,
            groupId,
            text: 'Rapid pending recovery',
          );
          expect(finalMessage.id, initialMessage.id);
          expect(finalMessage.status, 'sent');
          expect(finalMessage.inboxStored, isTrue);
          expect(finalMessage.inboxRetryPayload, isNull);
          expect(
            (await admin.msgRepo.getMessagesPage(groupId, limit: 20)).where(
              (message) =>
                  !message.isIncoming &&
                  message.text == 'Rapid pending recovery',
            ),
            hasLength(1),
          );
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:publish'),
            hasLength(1),
          );
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
            hasLength(2),
          );

          final liveAfterResume = await liveReader.loadGroupMessages(groupId);
          expect(
            liveAfterResume.where((message) => message.id == initialMessage.id),
            hasLength(1),
          );

          final inboxRecoveredMessages = await inboxReader.loadGroupMessages(
            groupId,
          );
          expect(
            inboxRecoveredMessages.where(
              (message) => message.id == initialMessage.id,
            ),
            hasLength(1),
          );

          admin.dispose();
          liveReader.dispose();
          inboxReader.dispose();
        },
      );

      test(
        'UP-008 pending outbound group message survives restart and reconciles through inbox retry',
        () async {
          final adminBridge = _Section10MirroringBridge(
            network: network,
            msgRepo: InMemoryGroupMessageRepository(),
            groupRepo: InMemoryGroupRepository(),
            inboxStoreFailuresRemaining: 1,
          );
          final admin = GroupTestUser.create(
            peerId: 'admin-up008-restart-peer',
            username: 'Alice',
            network: network,
            bridge: adminBridge,
          );
          final liveReader = GroupTestUser.create(
            peerId: 'reader-up008-live-peer',
            username: 'Bob',
            network: network,
          );
          final inboxReader = GroupTestUser.create(
            peerId: 'reader-up008-inbox-peer',
            username: 'Carol',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final inboxBridge = inboxReader.bridge as _CursorInboxBridge;

          const groupId = 'group-up008-pending-restart';
          const messageId = 'up008-pending-restart-id';
          const text = 'UP-008 pending restart recovery';
          await admin.createGroup(groupId: groupId, name: 'UP-008 Restart');
          await admin.addMember(groupId: groupId, invitee: liveReader);
          await admin.addMember(groupId: groupId, invitee: inboxReader);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(liveReader, groupId, 1, 'k1');
          await _saveKey(inboxReader, groupId, 1, 'k1');
          network.unsubscribe(groupId, inboxReader.peerId);

          admin.start();
          liveReader.start();
          inboxReader.start();

          final (initialResult, initialMessage) = await admin
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: text,
                messageId: messageId,
              );

          expect(initialResult, SendGroupMessageResult.success);
          expect(initialMessage, isNotNull);
          expect(initialMessage!.id, messageId);
          expect(initialMessage.status, 'pending');
          expect(initialMessage.inboxStored, isFalse);
          expect(initialMessage.inboxRetryPayload, isNotNull);
          expect(
            (await admin.msgRepo.getMessagesWithFailedInboxStore()).map(
              (row) => row.id,
            ),
            [messageId],
          );

          await pump();
          final liveBeforeRestart = await liveReader.loadGroupMessages(groupId);
          expect(
            liveBeforeRestart.where((message) => message.id == messageId),
            hasLength(1),
          );
          expect(await inboxReader.loadGroupMessages(groupId), isEmpty);

          admin.groupMessageListener.dispose();
          var resumeRetryCount = 0;
          await simulateBackgroundForegroundCycle(
            bridge: admin.bridge,
            p2pService: FakeP2PService(),
            messageRepo: InMemoryMessageRepository(),
            groupMsgRepo: admin.msgRepo,
            retryFailedGroupInboxStoresFn: () async {
              final retried = await retryFailedGroupInboxStores(
                bridge: admin.bridge,
                msgRepo: admin.msgRepo,
              );
              resumeRetryCount += retried;
              if (retried > 0) {
                _injectInboxMessageFromLatestStore(
                  senderBridge: admin.bridge,
                  receiverBridge: inboxBridge,
                  receiverPeerId: inboxReader.peerId,
                  groupId: groupId,
                );
              }
              return retried;
            },
          );

          expect(resumeRetryCount, 1);
          await drainGroupOfflineInbox(
            bridge: inboxReader.bridge,
            groupRepo: inboxReader.groupRepo,
            msgRepo: inboxReader.msgRepo,
          );

          final finalMessage = await admin.msgRepo.getMessage(messageId);
          expect(finalMessage, isNotNull);
          expect(finalMessage!.status, 'sent');
          expect(finalMessage.inboxStored, isTrue);
          expect(finalMessage.inboxRetryPayload, isNull);
          expect(
            (await admin.loadGroupMessages(groupId)).where(
              (message) =>
                  !message.isIncoming &&
                  message.id == messageId &&
                  (message.status == 'pending' || message.status == 'failed'),
            ),
            isEmpty,
          );
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:publish'),
            hasLength(1),
          );
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
            hasLength(2),
          );

          final liveAfterRestart = await liveReader.loadGroupMessages(groupId);
          expect(
            liveAfterRestart.where((message) => message.id == messageId),
            hasLength(1),
          );
          final inboxAfterRestart = await inboxReader.loadGroupMessages(
            groupId,
          );
          expect(
            inboxAfterRestart.where((message) => message.id == messageId),
            hasLength(1),
          );

          admin.dispose();
          liveReader.dispose();
          inboxReader.dispose();
        },
      );

      test(
        'IR-008 failed inbox retrieve retries same cursor and drains missed fake-network message once',
        () async {
          final admin = GroupTestUser.create(
            peerId: 'admin-ir008-retrieve-peer',
            username: 'Alice',
            network: network,
            bridge: _Section10MirroringBridge(
              network: network,
              msgRepo: InMemoryGroupMessageRepository(),
              groupRepo: InMemoryGroupRepository(),
            ),
          );
          final bobBridge = _FailFirstCursorInboxBridge();
          final bob = GroupTestUser.create(
            peerId: 'reader-ir008-retrieve-peer',
            username: 'Bob',
            network: network,
            bridge: bobBridge,
          );

          const groupId = 'group-ir008-retrieve-retry';
          const text = 'IR-008 retrieve retry delivery';
          await admin.createGroup(groupId: groupId, name: 'IR008 Retrieve');
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');
          network.unsubscribe(groupId, bob.peerId);

          admin.start();
          bob.start();

          final (sendResult, sent) = await admin.sendGroupMessageViaBridge(
            groupId: groupId,
            text: text,
          );

          expect(sendResult, SendGroupMessageResult.successNoPeers);
          expect(sent, isNotNull);
          expect(sent!.inboxStored, isTrue);
          _injectInboxMessageFromLatestStore(
            senderBridge: admin.bridge,
            receiverBridge: bobBridge,
            receiverPeerId: bob.peerId,
            groupId: groupId,
          );

          final failedDrain = await drainGroupOfflineInbox(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            msgRepo: bob.msgRepo,
            selfPeerId: bob.peerId,
          );

          expect(failedDrain.isSuccessful, isFalse);
          expect(failedDrain.errorCount, 1);
          expect(await bob.loadGroupMessages(groupId), isEmpty);
          expect(await bob.msgRepo.getInboxCursor(groupId), isNull);
          expect(
            await bob.msgRepo.getReceiptsForMessage(groupId, sent.id),
            isEmpty,
          );
          final failedCursorCommands = bobBridge.sentMessages
              .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
              .where((message) => message['cmd'] == 'group:inboxRetrieveCursor')
              .toList(growable: false);
          expect(failedCursorCommands, hasLength(1));
          expect(failedCursorCommands.single['payload']['cursor'], '');

          final retryDrain = await drainGroupOfflineInbox(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            msgRepo: bob.msgRepo,
            selfPeerId: bob.peerId,
          );

          expect(retryDrain.isSuccessful, isTrue);
          final bobMessages = await bob.loadGroupMessages(groupId);
          expect(
            bobMessages.where(
              (message) =>
                  message.isIncoming &&
                  message.id == sent.id &&
                  message.text == text,
            ),
            hasLength(1),
          );
          expect(
            await bob.msgRepo.getReceiptsForMessage(groupId, sent.id),
            hasLength(1),
          );
          expect(
            await bob.msgRepo.getInboxCursor(groupId),
            startsWith(groupInboxSyntheticSinceCursorPrefix),
          );
          final allCursorCommands = bobBridge.sentMessages
              .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
              .where((message) => message['cmd'] == 'group:inboxRetrieveCursor')
              .toList(growable: false);
          expect(allCursorCommands, hasLength(2));
          expect(allCursorCommands[0]['payload']['cursor'], '');
          expect(allCursorCommands[1]['payload']['cursor'], '');

          admin.dispose();
          bob.dispose();
        },
      );

      test(
        'IR-009 failed replay persistence retries same cursor and stores missed fake-network message once',
        () async {
          final admin = GroupTestUser.create(
            peerId: 'admin-ir009-persist-peer',
            username: 'Alice',
            network: network,
            bridge: _Section10MirroringBridge(
              network: network,
              msgRepo: InMemoryGroupMessageRepository(),
              groupRepo: InMemoryGroupRepository(),
            ),
          );
          final bobBridge = _CursorInboxBridge();
          final bob = GroupTestUser.create(
            peerId: 'reader-ir009-persist-peer',
            username: 'Bob',
            network: network,
            bridge: bobBridge,
          );

          const groupId = 'group-ir009-persist-retry';
          const text = 'IR-009 persistence retry delivery';
          await admin.createGroup(groupId: groupId, name: 'IR009 Persist');
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');
          network.unsubscribe(groupId, bob.peerId);

          admin.start();
          bob.start();

          final (sendResult, sent) = await admin.sendGroupMessageViaBridge(
            groupId: groupId,
            text: text,
          );

          expect(sendResult, SendGroupMessageResult.successNoPeers);
          expect(sent, isNotNull);
          expect(sent!.inboxStored, isTrue);
          _injectInboxMessageFromLatestStore(
            senderBridge: admin.bridge,
            receiverBridge: bobBridge,
            receiverPeerId: bob.peerId,
            groupId: groupId,
          );
          bob.msgRepo.failSaveMessageIds.add(sent.id);

          final failedDrain = await drainGroupOfflineInbox(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            msgRepo: bob.msgRepo,
            selfPeerId: bob.peerId,
          );

          expect(failedDrain.isSuccessful, isFalse);
          expect(failedDrain.errorCount, 1);
          expect(await bob.loadGroupMessages(groupId), isEmpty);
          expect(await bob.msgRepo.getInboxCursor(groupId), isNull);
          expect(
            await bob.msgRepo.getReceiptsForMessage(groupId, sent.id),
            isEmpty,
          );
          final failedCursorCommands = bobBridge.sentMessages
              .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
              .where((message) => message['cmd'] == 'group:inboxRetrieveCursor')
              .toList(growable: false);
          expect(failedCursorCommands, hasLength(1));
          expect(failedCursorCommands.single['payload']['cursor'], '');

          bob.msgRepo.failSaveMessageIds.remove(sent.id);
          final retryDrain = await drainGroupOfflineInbox(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            msgRepo: bob.msgRepo,
            selfPeerId: bob.peerId,
          );

          expect(retryDrain.isSuccessful, isTrue);
          final bobMessages = await bob.loadGroupMessages(groupId);
          expect(
            bobMessages.where(
              (message) =>
                  message.isIncoming &&
                  message.id == sent.id &&
                  message.text == text,
            ),
            hasLength(1),
          );
          expect(
            await bob.msgRepo.getReceiptsForMessage(groupId, sent.id),
            hasLength(1),
          );
          expect(
            await bob.msgRepo.getInboxCursor(groupId),
            startsWith(groupInboxSyntheticSinceCursorPrefix),
          );
          final allCursorCommands = bobBridge.sentMessages
              .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
              .where((message) => message['cmd'] == 'group:inboxRetrieveCursor')
              .toList(growable: false);
          expect(allCursorCommands, hasLength(2));
          expect(allCursorCommands[0]['payload']['cursor'], '');
          expect(allCursorCommands[1]['payload']['cursor'], '');

          admin.dispose();
          bob.dispose();
        },
      );

      test(
        'GR-017 recovery preserves failed direct and pending inbox retry state',
        () async {
          final adminBridge = _Section10MirroringBridge(
            network: network,
            msgRepo: InMemoryGroupMessageRepository(),
            groupRepo: InMemoryGroupRepository(),
            publishFailuresRemaining: 1,
            inboxStoreFailuresRemaining: 1,
          );
          final admin = GroupTestUser.create(
            peerId: 'admin-gr017-peer',
            username: 'Alice',
            network: network,
            bridge: adminBridge,
          );
          final liveReader = GroupTestUser.create(
            peerId: 'reader-gr017-live-peer',
            username: 'Bob',
            network: network,
          );
          final inboxReader = GroupTestUser.create(
            peerId: 'reader-gr017-inbox-peer',
            username: 'Carol',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final inboxBridge = inboxReader.bridge as _CursorInboxBridge;

          const groupId = 'group-gr017-retry-preserve';
          const directRetryId = 'gr017-direct-retry';
          const inboxRetryId = 'gr017-inbox-retry';
          const directRetryText = 'GR017 direct retry survives recovery';
          const inboxRetryText = 'GR017 inbox retry survives recovery';

          await admin.createGroup(groupId: groupId, name: 'GR017 Retry');
          await admin.addMember(groupId: groupId, invitee: liveReader);
          await admin.addMember(groupId: groupId, invitee: inboxReader);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(liveReader, groupId, 1, 'k1');
          await _saveKey(inboxReader, groupId, 1, 'k1');
          network.unsubscribe(groupId, inboxReader.peerId);

          admin.start();
          liveReader.start();
          inboxReader.start();

          final (directResult, directMessage) = await admin
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: directRetryText,
                messageId: directRetryId,
              );
          expect(directResult, SendGroupMessageResult.error);
          expect(directMessage, isNotNull);
          expect(directMessage!.status, 'failed');
          expect(directMessage.inboxStored, isFalse);
          expect(directMessage.inboxRetryPayload, isNotNull);

          adminBridge.inboxStoreFailuresRemaining = 1;
          final (inboxResult, inboxMessage) = await admin
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: inboxRetryText,
                messageId: inboxRetryId,
              );
          expect(inboxResult, SendGroupMessageResult.success);
          expect(inboxMessage, isNotNull);
          expect(inboxMessage!.status, 'pending');
          expect(inboxMessage.inboxStored, isFalse);
          expect(inboxMessage.inboxRetryPayload, isNotNull);

          await pumpUntilAsync(() async {
            final liveMessages = await liveReader.loadGroupMessages(groupId);
            return liveMessages.any((message) => message.id == inboxRetryId);
          }, maxPumps: 120);

          final retryOrder = <String>[];
          await handleAppResumed(
            bridge: admin.bridge,
            p2pService: FakeP2PService(recoveryMethod: 'watchdog_restart'),
            groupRepo: admin.groupRepo,
            groupMsgRepo: admin.msgRepo,
            retryFailedGroupMessagesFn: () async {
              retryOrder.add('retryFailedGroupMessages');
              return retryFailedGroupMessages(
                groupMsgRepo: admin.msgRepo,
                groupRepo: admin.groupRepo,
                identityRepo: _Section10IdentityRepository(
                  _identityForUser(admin),
                ),
                bridge: admin.bridge,
                mediaAttachmentRepo: admin.mediaAttachmentRepo,
              );
            },
            retryFailedGroupInboxStoresFn: () async {
              retryOrder.add('retryFailedGroupInboxStores');
              return retryFailedGroupInboxStores(
                bridge: admin.bridge,
                msgRepo: admin.msgRepo,
              );
            },
          );

          expect(retryOrder, [
            'retryFailedGroupMessages',
            'retryFailedGroupInboxStores',
          ]);

          final directAfterRecovery = await admin.msgRepo.getMessage(
            directRetryId,
          );
          final inboxAfterRecovery = await admin.msgRepo.getMessage(
            inboxRetryId,
          );
          expect(directAfterRecovery, isNotNull);
          expect(directAfterRecovery!.status, 'sent');
          expect(directAfterRecovery.inboxStored, isTrue);
          expect(directAfterRecovery.inboxRetryPayload, isNull);
          expect(inboxAfterRecovery, isNotNull);
          expect(inboxAfterRecovery!.status, 'sent');
          expect(inboxAfterRecovery.inboxStored, isTrue);
          expect(inboxAfterRecovery.inboxRetryPayload, isNull);

          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:publish'),
            hasLength(3),
          );
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
            hasLength(4),
          );

          final storeByMessageId = <String, Map<String, dynamic>>{};
          for (final payload in bridgePayloads(
            admin.bridge,
            'group:inboxStore',
          )) {
            final recipients =
                (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
                    .cast<String>();
            if (!recipients.contains(inboxReader.peerId)) continue;

            final storedMessage = payload['message'] as String;
            final decoded = _decodedGroupReplayPayload(storedMessage);
            final messageId = decoded['messageId'] as String?;
            if (messageId == directRetryId || messageId == inboxRetryId) {
              storeByMessageId[messageId!] = payload;
            }
          }
          expect(storeByMessageId.keys.toSet(), {directRetryId, inboxRetryId});

          inboxBridge.addPage(groupId, '', [
            for (final messageId in [directRetryId, inboxRetryId])
              {
                'from': admin.peerId,
                'message': storeByMessageId[messageId]!['message'] as String,
                'timestamp': DateTime.now().millisecondsSinceEpoch,
              },
          ], '');
          await drainGroupOfflineInbox(
            bridge: inboxReader.bridge,
            groupRepo: inboxReader.groupRepo,
            msgRepo: inboxReader.msgRepo,
          );

          final liveMessages = await liveReader.loadGroupMessages(groupId);
          expect(
            liveMessages.where((message) => message.id == directRetryId),
            hasLength(1),
          );
          expect(
            liveMessages.where((message) => message.id == inboxRetryId),
            hasLength(1),
          );

          final inboxMessages = await inboxReader.loadGroupMessages(groupId);
          expect(
            inboxMessages.where(
              (message) =>
                  message.isIncoming &&
                  message.id == directRetryId &&
                  message.text == directRetryText,
            ),
            hasLength(1),
          );
          expect(
            inboxMessages.where(
              (message) =>
                  message.isIncoming &&
                  message.id == inboxRetryId &&
                  message.text == inboxRetryText,
            ),
            hasLength(1),
          );

          admin.dispose();
          liveReader.dispose();
          inboxReader.dispose();
        },
      );

      test('stuck sending recovery after background', () async {
        final publishGate = Completer<void>();
        final admin = GroupTestUser.create(
          peerId: 'admin-stuck-peer',
          username: 'Alice',
          network: network,
          bridge: _Section10MirroringBridge(
            network: network,
            msgRepo: InMemoryGroupMessageRepository(),
            groupRepo: InMemoryGroupRepository(),
            commandGates: {'group:publish': publishGate},
          ),
        );
        final bob = GroupTestUser.create(
          peerId: 'reader-stuck-peer',
          username: 'Bob',
          network: network,
        );

        const groupId = 'group-stuck-send';
        await admin.createGroup(groupId: groupId, name: 'Stuck Send');
        await admin.addMember(groupId: groupId, invitee: bob);
        await _saveKey(admin, groupId, 1, 'k1');
        await _saveKey(bob, groupId, 1, 'k1');

        admin.start();
        bob.start();

        final sendFuture = admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'Slow send while backgrounded',
        );
        await pump();

        await simulateBackgroundForegroundCycle(
          bridge: admin.bridge,
          p2pService: FakeP2PService(),
          messageRepo: InMemoryMessageRepository(),
          groupMsgRepo: admin.msgRepo,
          afterPause: () async {
            final paused = await _latestOutgoingMessage(
              admin.msgRepo,
              groupId,
              text: 'Slow send while backgrounded',
            );
            expect(paused.status, 'failed');
          },
          afterResume: () async {
            publishGate.complete();
            final (result, sent) = await sendFuture;
            expect(result, SendGroupMessageResult.success);
            expect(sent, isNotNull);
          },
        );

        await pump();
        final finalMessage = await _latestOutgoingMessage(
          admin.msgRepo,
          groupId,
          text: 'Slow send while backgrounded',
        );
        expect(finalMessage.status, 'sent');
        expect(finalMessage.inboxStored, isTrue);

        final bobMessages = await bob.loadGroupMessages(groupId);
        expect(
          bobMessages.any(
            (message) => message.text == 'Slow send while backgrounded',
          ),
          isTrue,
        );

        admin.dispose();
        bob.dispose();
      });

      test(
        'NW-011 backgrounded sender send is delivered or remains retryable with no invisible send',
        () async {
          final publishGate = Completer<void>();
          final adminBridge = _Section10MirroringBridge(
            network: network,
            msgRepo: InMemoryGroupMessageRepository(),
            groupRepo: InMemoryGroupRepository(),
            commandGates: {'group:publish': publishGate},
          );
          final admin = GroupTestUser.create(
            peerId: 'admin-nw011-background-peer',
            username: 'Alice',
            network: network,
            bridge: adminBridge,
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-nw011-background-peer',
            username: 'Bob',
            network: network,
          );

          const groupId = 'group-nw011-background-send';
          const messageId = 'nw011-background-send-id';
          const text = 'NW-011 background send';
          await admin.createGroup(groupId: groupId, name: 'NW-011');
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');

          admin.start();
          bob.start();

          final sendFuture = admin.sendGroupMessageViaBridge(
            groupId: groupId,
            text: text,
            messageId: messageId,
          );
          await pumpUntilAsync(() async {
            return adminBridge.commandLog.contains('group:publish') &&
                (await admin.msgRepo.getMessage(messageId)) != null;
          });

          await simulateBackgroundForegroundCycle(
            bridge: admin.bridge,
            p2pService: FakeP2PService(),
            messageRepo: InMemoryMessageRepository(),
            groupMsgRepo: admin.msgRepo,
            afterPause: () async {
              final paused = await admin.msgRepo.getMessage(messageId);
              expect(paused, isNotNull);
              expect(paused!.status, 'failed');
              expect(paused.wireEnvelope, isNotNull);
              expect(paused.inboxRetryPayload, isNotNull);
              final bobDuringPause = await bob.loadGroupMessages(groupId);
              expect(
                bobDuringPause.where((message) => message.id == messageId),
                isEmpty,
              );
            },
            afterResume: () async {
              publishGate.complete();
              final (result, sent) = await sendFuture;
              expect(result, SendGroupMessageResult.success);
              expect(sent, isNotNull);
            },
          );

          await pump();
          final senderRows = await admin.loadGroupMessages(groupId);
          final senderMatches = senderRows
              .where((message) => message.id == messageId)
              .toList(growable: false);
          expect(senderMatches, hasLength(1));
          expect(senderMatches.single.status, 'sent');
          expect(senderMatches.single.inboxStored, isTrue);
          expect(
            senderRows.where(
              (message) =>
                  !message.isIncoming &&
                  message.text == text &&
                  (message.status == 'pending' || message.status == 'failed'),
            ),
            isEmpty,
          );

          final bobRows = await bob.loadGroupMessages(groupId);
          expect(
            bobRows.where((message) => message.id == messageId),
            hasLength(1),
          );
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:publish'),
            hasLength(1),
          );
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
            hasLength(1),
          );

          admin.dispose();
          bob.dispose();
        },
      );

      test('partial delivery with inbox drain completion', () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-partial-peer',
          username: 'Alice',
          network: network,
        );
        final onlineReader = GroupTestUser.create(
          peerId: 'reader-online-peer',
          username: 'Bob',
          network: network,
        );
        final inboxReaderOne = GroupTestUser.create(
          peerId: 'reader-inbox-1-peer',
          username: 'Carol',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final inboxReaderTwo = GroupTestUser.create(
          peerId: 'reader-inbox-2-peer',
          username: 'Dave',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final inboxBridgeOne = inboxReaderOne.bridge as _CursorInboxBridge;
        final inboxBridgeTwo = inboxReaderTwo.bridge as _CursorInboxBridge;

        const groupId = 'group-partial-delivery';
        await admin.createGroup(groupId: groupId, name: 'Partial Delivery');
        await admin.addMember(groupId: groupId, invitee: onlineReader);
        await admin.addMember(groupId: groupId, invitee: inboxReaderOne);
        await admin.addMember(groupId: groupId, invitee: inboxReaderTwo);
        await _saveKey(admin, groupId, 1, 'k1');
        await _saveKey(onlineReader, groupId, 1, 'k1');
        await _saveKey(inboxReaderOne, groupId, 1, 'k1');
        await _saveKey(inboxReaderTwo, groupId, 1, 'k1');
        network.unsubscribe(groupId, inboxReaderOne.peerId);
        network.unsubscribe(groupId, inboxReaderTwo.peerId);

        admin.start();
        onlineReader.start();
        inboxReaderOne.start();
        inboxReaderTwo.start();

        final (result, sent) = await admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'Partial delivery',
        );

        expect(result, SendGroupMessageResult.success);
        expect(sent, isNotNull);
        expect(sent!.status, 'sent');

        await pump();
        final preDrainOnlineMessages = await onlineReader.loadGroupMessages(
          groupId,
        );
        expect(
          preDrainOnlineMessages.where(
            (message) => message.text == 'Partial delivery',
          ),
          hasLength(1),
        );
        expect(await inboxReaderOne.loadGroupMessages(groupId), isEmpty);
        expect(await inboxReaderTwo.loadGroupMessages(groupId), isEmpty);

        _injectInboxMessageFromLatestStore(
          senderBridge: admin.bridge,
          receiverBridge: inboxBridgeOne,
          receiverPeerId: inboxReaderOne.peerId,
          groupId: groupId,
        );
        _injectInboxMessageFromLatestStore(
          senderBridge: admin.bridge,
          receiverBridge: inboxBridgeTwo,
          receiverPeerId: inboxReaderTwo.peerId,
          groupId: groupId,
        );

        await drainGroupOfflineInbox(
          bridge: inboxReaderOne.bridge,
          groupRepo: inboxReaderOne.groupRepo,
          msgRepo: inboxReaderOne.msgRepo,
        );
        await drainGroupOfflineInbox(
          bridge: inboxReaderTwo.bridge,
          groupRepo: inboxReaderTwo.groupRepo,
          msgRepo: inboxReaderTwo.msgRepo,
        );

        final onlineMessages = await onlineReader.loadGroupMessages(groupId);
        final inboxMessagesOne = await inboxReaderOne.loadGroupMessages(
          groupId,
        );
        final inboxMessagesTwo = await inboxReaderTwo.loadGroupMessages(
          groupId,
        );
        expect(
          onlineMessages.where((message) => message.text == 'Partial delivery'),
          hasLength(1),
        );
        expect(
          inboxMessagesOne.where(
            (message) => message.text == 'Partial delivery',
          ),
          hasLength(1),
        );
        expect(
          inboxMessagesTwo.where(
            (message) => message.text == 'Partial delivery',
          ),
          hasLength(1),
        );

        admin.dispose();
        onlineReader.dispose();
        inboxReaderOne.dispose();
        inboxReaderTwo.dispose();
      });

      test(
        'DE-006 partial live fanout does not claim offline recipient receipt before inbox drain',
        () async {
          final admin = GroupTestUser.create(
            peerId: 'admin-de006-peer',
            username: 'Alice',
            network: network,
          );
          final onlineReader = GroupTestUser.create(
            peerId: 'reader-de006-online-peer',
            username: 'Bob',
            network: network,
          );
          final inboxReader = GroupTestUser.create(
            peerId: 'reader-de006-inbox-peer',
            username: 'Carol',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          addTearDown(() {
            admin.dispose();
            onlineReader.dispose();
            inboxReader.dispose();
          });

          final inboxBridge = inboxReader.bridge as _CursorInboxBridge;
          const groupId = 'group-de006-partial-fanout';
          const text = 'DE-006 partial live fanout';
          await admin.createGroup(groupId: groupId, name: 'DE-006 Partial');
          await admin.addMember(groupId: groupId, invitee: onlineReader);
          await admin.addMember(groupId: groupId, invitee: inboxReader);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(onlineReader, groupId, 1, 'k1');
          await _saveKey(inboxReader, groupId, 1, 'k1');
          network.unsubscribe(groupId, inboxReader.peerId);

          admin.start();
          onlineReader.start();
          inboxReader.start();

          final (result, sent) = await admin.sendGroupMessageViaBridge(
            groupId: groupId,
            text: text,
            messageId: 'de006-partial-live-fanout',
          );

          expect(result, SendGroupMessageResult.success);
          expect(sent, isNotNull);
          expect(sent!.status, 'sent');
          expect(sent.status, isNot('delivered'));

          await pump();
          final onlineBeforeDrain = await onlineReader.loadGroupMessages(
            groupId,
          );
          expect(
            onlineBeforeDrain.where((message) => message.text == text),
            hasLength(1),
          );
          expect(await inboxReader.loadGroupMessages(groupId), isEmpty);
          expect(
            await admin.msgRepo.getReceiptsForMessage(
              groupId,
              sent.id,
              receiptType: groupMessageReceiptTypeDelivered,
            ),
            isEmpty,
          );
          expect(
            await admin.msgRepo.getReceiptsForMessage(
              groupId,
              sent.id,
              receiptType: groupMessageReceiptTypeRead,
            ),
            isEmpty,
          );

          _injectInboxMessageFromLatestStore(
            senderBridge: admin.bridge,
            receiverBridge: inboxBridge,
            receiverPeerId: inboxReader.peerId,
            groupId: groupId,
          );
          await drainGroupOfflineInbox(
            bridge: inboxReader.bridge,
            groupRepo: inboxReader.groupRepo,
            msgRepo: inboxReader.msgRepo,
          );

          final inboxMessages = await inboxReader.loadGroupMessages(groupId);
          expect(
            inboxMessages.where((message) => message.text == text),
            hasLength(1),
          );
          final senderRows = await admin.loadGroupMessages(groupId);
          expect(
            senderRows.where((message) => message.id == sent.id),
            hasLength(1),
          );
          expect(
            await admin.msgRepo.getReceiptsForMessage(
              groupId,
              sent.id,
              receiptType: groupMessageReceiptTypeDelivered,
            ),
            isEmpty,
          );
          expect(
            await admin.msgRepo.getReceiptsForMessage(
              groupId,
              sent.id,
              receiptType: groupMessageReceiptTypeRead,
            ),
            isEmpty,
          );
        },
      );

      test(
        'DE-007 zero-peer publish reaches active Bob and Charlie through replay',
        () async {
          final admin = GroupTestUser.create(
            peerId: 'admin-de007-zero-peer',
            username: 'Alice',
            network: network,
            bridge: ZeroPeerPublishBridge(),
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-de007-bob',
            username: 'Bob',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final charlie = GroupTestUser.create(
            peerId: 'reader-de007-charlie',
            username: 'Charlie',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          addTearDown(() {
            admin.dispose();
            bob.dispose();
            charlie.dispose();
          });

          final bobBridge = bob.bridge as _CursorInboxBridge;
          final charlieBridge = charlie.bridge as _CursorInboxBridge;
          const groupId = 'group-de007-zero-peer';
          const messageId = 'de007-zero-peer-replay';
          const text = 'DE-007 zero-peer durable replay';
          await admin.createGroup(groupId: groupId, name: 'DE-007 Zero Peer');
          await admin.addMember(groupId: groupId, invitee: bob);
          await admin.addMember(groupId: groupId, invitee: charlie);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');
          await _saveKey(charlie, groupId, 1, 'k1');
          network.unsubscribe(groupId, bob.peerId);
          network.unsubscribe(groupId, charlie.peerId);

          admin.start();
          bob.start();
          charlie.start();

          final (result, sent) = await admin.sendGroupMessageViaBridge(
            groupId: groupId,
            text: text,
            messageId: messageId,
          );

          expect(result, SendGroupMessageResult.successNoPeers);
          expect(sent, isNotNull);
          expect(sent!.status, 'sent');
          expect(sent.inboxStored, isTrue);
          expect(sent.inboxRetryPayload, isNull);
          expect(admin.bridge.commandLog, contains('group:publish'));
          expect(admin.bridge.commandLog, contains('group:inboxStore'));

          final inboxPayload = latestBridgePayload(
            admin.bridge,
            'group:inboxStore',
          );
          expect(
            (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
            unorderedEquals([bob.peerId, charlie.peerId]),
          );

          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(await bob.loadGroupMessages(groupId), isEmpty);
          expect(await charlie.loadGroupMessages(groupId), isEmpty);

          _injectInboxMessageFromLatestStore(
            senderBridge: admin.bridge,
            receiverBridge: bobBridge,
            receiverPeerId: bob.peerId,
            groupId: groupId,
          );
          _injectInboxMessageFromLatestStore(
            senderBridge: admin.bridge,
            receiverBridge: charlieBridge,
            receiverPeerId: charlie.peerId,
            groupId: groupId,
          );

          await drainGroupOfflineInbox(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            msgRepo: bob.msgRepo,
          );
          await drainGroupOfflineInbox(
            bridge: charlie.bridge,
            groupRepo: charlie.groupRepo,
            msgRepo: charlie.msgRepo,
          );

          final bobMessages = await bob.loadGroupMessages(groupId);
          final charlieMessages = await charlie.loadGroupMessages(groupId);
          expect(
            bobMessages.where(
              (message) =>
                  message.isIncoming &&
                  message.id == messageId &&
                  message.text == text,
            ),
            hasLength(1),
          );
          expect(
            charlieMessages.where(
              (message) =>
                  message.isIncoming &&
                  message.id == messageId &&
                  message.text == text,
            ),
            hasLength(1),
          );
          expect(
            await admin.msgRepo.getReceiptsForMessage(
              groupId,
              messageId,
              receiptType: groupMessageReceiptTypeDelivered,
            ),
            isEmpty,
          );
          expect(
            await admin.msgRepo.getReceiptsForMessage(
              groupId,
              messageId,
              receiptType: groupMessageReceiptTypeRead,
            ),
            isEmpty,
          );
        },
      );

      test(
        'NW-007 zero topic peers keep membership and replay recovery for all active members',
        () async {
          final trace = <String>[];
          final bobBridge = _RejoiningCursorInboxBridge(
            network: network,
            peerId: 'reader-nw007-bob',
            trace: trace,
          );
          final charlieBridge = _RejoiningCursorInboxBridge(
            network: network,
            peerId: 'reader-nw007-charlie',
            trace: trace,
          );
          final alice = GroupTestUser.create(
            peerId: 'alice-nw007-zero-topic',
            username: 'Alice',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-nw007-bob',
            username: 'Bob',
            network: network,
            bridge: bobBridge,
          );
          final charlie = GroupTestUser.create(
            peerId: 'reader-nw007-charlie',
            username: 'Charlie',
            network: network,
            bridge: charlieBridge,
          );
          const groupId = 'group-nw007-zero-topic-peers';
          const messageId = 'nw007-zero-topic-replay';
          const text = 'NW-007 zero topic peer replay';

          Future<Set<String>> memberPeerIds(GroupTestUser user) async {
            return (await user.groupRepo.getMembers(
              groupId,
            )).map((member) => member.peerId).toSet();
          }

          Future<int> incomingTextCount(GroupTestUser user) async {
            return (await user.loadGroupMessages(groupId))
                .where((message) => message.isIncoming && message.text == text)
                .length;
          }

          bool hasRemovalSignal(List<GroupMessage> messages) {
            return messages.any(
              (message) =>
                  message.text.contains('member_removed') ||
                  message.text.contains('removed'),
            );
          }

          try {
            await alice.createGroup(groupId: groupId, name: 'NW-007');
            await alice.addMember(groupId: groupId, invitee: bob);
            await alice.addMember(groupId: groupId, invitee: charlie);
            await _saveKey(alice, groupId, 7, 'nw007-key');
            await _saveKey(bob, groupId, 7, 'nw007-key');
            await _saveKey(charlie, groupId, 7, 'nw007-key');

            alice.start();
            bob.start();
            charlie.start();

            await alice.broadcastMemberAdded(
              groupId: groupId,
              newMember: charlie,
            );
            final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
            await pumpUntilAsync(() async {
              return (await memberPeerIds(
                    alice,
                  )).containsAll(expectedMembers) &&
                  (await memberPeerIds(bob)).containsAll(expectedMembers) &&
                  (await memberPeerIds(charlie)).containsAll(expectedMembers);
            }, maxPumps: 80);
            final aliceMembersBefore = await memberPeerIds(alice);
            final bobMembersBefore = await memberPeerIds(bob);
            final charlieMembersBefore = await memberPeerIds(charlie);
            final aliceEpochBefore = (await alice.groupRepo.getLatestKey(
              groupId,
            ))!.keyGeneration;
            final bobEpochBefore = (await bob.groupRepo.getLatestKey(
              groupId,
            ))!.keyGeneration;
            final charlieEpochBefore = (await charlie.groupRepo.getLatestKey(
              groupId,
            ))!.keyGeneration;

            network.unsubscribe(groupId, bob.peerId);
            network.unsubscribe(groupId, charlie.peerId);
            expect(network.isSubscribed(groupId, bob.peerId), isFalse);
            expect(network.isSubscribed(groupId, charlie.peerId), isFalse);
            expect(
              network
                  .getSubscribers(groupId)
                  .where((peerId) => peerId != alice.peerId),
              isEmpty,
            );

            final (result, sent) = await alice.sendGroupMessageViaBridge(
              groupId: groupId,
              text: text,
              messageId: messageId,
            );
            expect(result, SendGroupMessageResult.successNoPeers);
            expect(sent, isNotNull);
            expect(sent!.status, 'sent');
            expect(sent.inboxStored, isTrue);

            final inboxPayload = latestBridgePayload(
              alice.bridge,
              'group:inboxStore',
            );
            expect(
              (inboxPayload['recipientPeerIds'] as List<dynamic>)
                  .cast<String>(),
              unorderedEquals([bob.peerId, charlie.peerId]),
            );
            await Future<void>.delayed(const Duration(milliseconds: 100));
            expect(await incomingTextCount(bob), 0);
            expect(await incomingTextCount(charlie), 0);

            _injectInboxMessageFromLatestStore(
              senderBridge: alice.bridge,
              receiverBridge: bobBridge,
              receiverPeerId: bob.peerId,
              groupId: groupId,
            );
            _injectInboxMessageFromLatestStore(
              senderBridge: alice.bridge,
              receiverBridge: charlieBridge,
              receiverPeerId: charlie.peerId,
              groupId: groupId,
            );

            final bobRejoinResult = await rejoinGroupTopics(
              bridge: bob.bridge,
              groupRepo: bob.groupRepo,
              reason: RejoinReason.nodeRequestedRecovery,
            );
            final charlieRejoinResult = await rejoinGroupTopics(
              bridge: charlie.bridge,
              groupRepo: charlie.groupRepo,
              reason: RejoinReason.nodeRequestedRecovery,
            );
            expect(bobRejoinResult.errorCount, 0);
            expect(charlieRejoinResult.errorCount, 0);
            expect(network.isSubscribed(groupId, bob.peerId), isTrue);
            expect(network.isSubscribed(groupId, charlie.peerId), isTrue);

            final bobDrainResult = await drainGroupOfflineInbox(
              bridge: bob.bridge,
              groupRepo: bob.groupRepo,
              msgRepo: bob.msgRepo,
              groupMessageListener: bob.groupMessageListener,
              selfPeerId: bob.peerId,
            );
            final charlieDrainResult = await drainGroupOfflineInbox(
              bridge: charlie.bridge,
              groupRepo: charlie.groupRepo,
              msgRepo: charlie.msgRepo,
              groupMessageListener: charlie.groupMessageListener,
              selfPeerId: charlie.peerId,
            );
            expect(bobDrainResult.isSuccessful, isTrue);
            expect(charlieDrainResult.isSuccessful, isTrue);
            expect(await incomingTextCount(bob), 1);
            expect(await incomingTextCount(charlie), 1);
            expect(
              trace.where((entry) => entry == 'join:$groupId'),
              hasLength(2),
            );
            expect(
              trace.where((entry) => entry == 'drain:$groupId'),
              hasLength(2),
            );

            expect(await memberPeerIds(alice), aliceMembersBefore);
            expect(await memberPeerIds(bob), bobMembersBefore);
            expect(await memberPeerIds(charlie), charlieMembersBefore);
            expect(
              (await alice.groupRepo.getLatestKey(groupId))!.keyGeneration,
              aliceEpochBefore,
            );
            expect(
              (await bob.groupRepo.getLatestKey(groupId))!.keyGeneration,
              bobEpochBefore,
            );
            expect(
              (await charlie.groupRepo.getLatestKey(groupId))!.keyGeneration,
              charlieEpochBefore,
            );
            expect(
              hasRemovalSignal(await alice.loadGroupMessages(groupId)),
              isFalse,
            );
            expect(
              hasRemovalSignal(await bob.loadGroupMessages(groupId)),
              isFalse,
            );
            expect(
              hasRemovalSignal(await charlie.loadGroupMessages(groupId)),
              isFalse,
            );
          } finally {
            alice.dispose();
            bob.dispose();
            charlie.dispose();
          }
        },
      );

      test(
        'temporary partition replays missed backlog in cursor order and resumes live delivery after heal',
        () async {
          final admin = GroupTestUser.create(
            peerId: 'admin-partition-peer',
            username: 'Alice',
            network: network,
          );
          final onlineReader = GroupTestUser.create(
            peerId: 'reader-partition-online-peer',
            username: 'Bob',
            network: network,
          );
          final partitionedReader = GroupTestUser.create(
            peerId: 'reader-partition-offline-peer',
            username: 'Carol',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final partitionBridge =
              partitionedReader.bridge as _CursorInboxBridge;

          const groupId = 'group-partition-heal';
          await admin.createGroup(groupId: groupId, name: 'Partition Heal');
          await admin.addMember(groupId: groupId, invitee: onlineReader);
          await admin.addMember(groupId: groupId, invitee: partitionedReader);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(onlineReader, groupId, 1, 'k1');
          await _saveKey(partitionedReader, groupId, 1, 'k1');

          admin.start();
          onlineReader.start();
          partitionedReader.start();

          await admin.sendGroupMessage(groupId: groupId, text: 'Before split');
          await pump();

          var onlineTexts = (await onlineReader.loadGroupMessages(groupId))
              .where((message) => message.isIncoming)
              .map((message) => message.text)
              .toList(growable: false);
          var partitionedTexts =
              (await partitionedReader.loadGroupMessages(groupId))
                  .where((message) => message.isIncoming)
                  .map((message) => message.text)
                  .toList(growable: false);
          expect(onlineTexts, ['Before split']);
          expect(partitionedTexts, ['Before split']);

          network.unsubscribe(groupId, partitionedReader.peerId);
          expect(
            network.isSubscribed(groupId, partitionedReader.peerId),
            isFalse,
          );

          final (firstResult, firstSent) = await admin
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: 'During split 1',
              );
          final (secondResult, secondSent) = await admin
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: 'During split 2',
              );
          final (thirdResult, thirdSent) = await admin
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: 'During split 3',
              );

          expect(firstResult, SendGroupMessageResult.success);
          expect(firstSent, isNotNull);
          expect(firstSent!.inboxStored, isTrue);
          expect(secondResult, SendGroupMessageResult.success);
          expect(secondSent, isNotNull);
          expect(secondSent!.inboxStored, isTrue);
          expect(thirdResult, SendGroupMessageResult.success);
          expect(thirdSent, isNotNull);
          expect(thirdSent!.inboxStored, isTrue);

          await pumpUntilAsync(() async {
            final texts = (await onlineReader.loadGroupMessages(groupId))
                .where((message) => message.isIncoming)
                .map((message) => message.text)
                .toList(growable: false);
            return texts.length >= 4;
          }, maxPumps: 120);

          onlineTexts = (await onlineReader.loadGroupMessages(groupId))
              .where((message) => message.isIncoming)
              .map((message) => message.text)
              .toList(growable: false);
          partitionedTexts =
              (await partitionedReader.loadGroupMessages(groupId))
                  .where((message) => message.isIncoming)
                  .map((message) => message.text)
                  .toList(growable: false);
          expect(onlineTexts, [
            'Before split',
            'During split 1',
            'During split 2',
            'During split 3',
          ]);
          expect(
            partitionedTexts,
            ['Before split'],
            reason: 'Partitioned peer should miss split-window live delivery',
          );

          final inboxStores = bridgePayloads(admin.bridge, 'group:inboxStore');
          expect(inboxStores, hasLength(3));
          for (final payload in inboxStores) {
            expect(
              (payload['recipientPeerIds'] as List<dynamic>).cast<String>(),
              contains(partitionedReader.peerId),
            );
          }

          _addRelayStoredMessagePage(
            receiverBridge: partitionBridge,
            groupId: groupId,
            fromPeerId: admin.peerId,
            storedMessage: inboxStores[0]['message'] as String,
            nextCursor: 'cursor-partition-page-2',
          );
          _addRelayStoredMessagePage(
            receiverBridge: partitionBridge,
            groupId: groupId,
            fromPeerId: admin.peerId,
            storedMessage: inboxStores[1]['message'] as String,
            cursor: 'cursor-partition-page-2',
            nextCursor: 'cursor-partition-page-3',
          );
          _addRelayStoredMessagePage(
            receiverBridge: partitionBridge,
            groupId: groupId,
            fromPeerId: admin.peerId,
            storedMessage: inboxStores[2]['message'] as String,
            cursor: 'cursor-partition-page-3',
          );

          await rejoinGroupTopics(
            bridge: partitionedReader.bridge,
            groupRepo: partitionedReader.groupRepo,
          );
          await drainGroupOfflineInbox(
            bridge: partitionedReader.bridge,
            groupRepo: partitionedReader.groupRepo,
            msgRepo: partitionedReader.msgRepo,
          );
          network.subscribe(groupId, partitionedReader.peerId);
          expect(
            network.isSubscribed(groupId, partitionedReader.peerId),
            isTrue,
          );

          partitionedTexts =
              (await partitionedReader.loadGroupMessages(groupId))
                  .where((message) => message.isIncoming)
                  .map((message) => message.text)
                  .toList(growable: false);
          expect(partitionedTexts, [
            'Before split',
            'During split 1',
            'During split 2',
            'During split 3',
          ]);

          await admin.sendGroupMessage(groupId: groupId, text: 'After heal');
          await pump();

          onlineTexts = (await onlineReader.loadGroupMessages(groupId))
              .where((message) => message.isIncoming)
              .map((message) => message.text)
              .toList(growable: false);
          partitionedTexts =
              (await partitionedReader.loadGroupMessages(groupId))
                  .where((message) => message.isIncoming)
                  .map((message) => message.text)
                  .toList(growable: false);
          expect(onlineTexts, [
            'Before split',
            'During split 1',
            'During split 2',
            'During split 3',
            'After heal',
          ]);
          expect(partitionedTexts, [
            'Before split',
            'During split 1',
            'During split 2',
            'During split 3',
            'After heal',
          ]);

          final cursorCmds = partitionBridge.sentMessages
              .map((message) => jsonDecode(message) as Map<String, dynamic>)
              .where((message) => message['cmd'] == 'group:inboxRetrieveCursor')
              .toList(growable: false);
          expect(cursorCmds, hasLength(3));
          expect(cursorCmds[0]['payload']['cursor'], '');
          expect(cursorCmds[1]['payload']['cursor'], 'cursor-partition-page-2');
          expect(cursorCmds[2]['payload']['cursor'], 'cursor-partition-page-3');

          admin.dispose();
          onlineReader.dispose();
          partitionedReader.dispose();
        },
      );

      test(
        'NW-003 partitioned removal re-add drains Bob entitled backlog and filters Charlie removed-window before live heal',
        () async {
          final alice = GroupTestUser.create(
            peerId: 'admin-nw003-partition-peer',
            username: 'Alice',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'bob-nw003-partition-peer',
            username: 'Bob',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final charlie = GroupTestUser.create(
            peerId: 'charlie-nw003-partition-peer',
            username: 'Charlie',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final bobBridge = bob.bridge as _CursorInboxBridge;
          final charlieBridge = charlie.bridge as _CursorInboxBridge;

          const groupId = 'group-nw003-partition-readd-drain';
          const baselineText = 'NW-003 before partition';
          const removedWindowText = 'NW-003 removed-window during partition';
          const aliceAfterHeal = 'NW-003 Alice live after replay heal';
          const bobAfterHeal = 'NW-003 Bob live after replay heal';
          const charlieAfterHeal = 'NW-003 Charlie live after replay heal';

          await alice.createGroup(groupId: groupId, name: 'NW-003 Replay');
          await alice.addMember(groupId: groupId, invitee: bob);
          await alice.addMember(groupId: groupId, invitee: charlie);
          await _saveKey(alice, groupId, 1, 'nw003-k1');
          await _saveKey(bob, groupId, 1, 'nw003-k1');
          await _saveKey(charlie, groupId, 1, 'nw003-k1');

          alice.start();
          bob.start();
          charlie.start();
          await alice.sendGroupMessage(
            groupId: groupId,
            text: baselineText,
            messageId: 'nw003-baseline',
          );
          await pump();
          expect(
            (await bob.loadGroupMessages(
              groupId,
            )).map((message) => message.text),
            contains(baselineText),
          );
          expect(
            (await charlie.loadGroupMessages(
              groupId,
            )).map((message) => message.text),
            contains(baselineText),
          );

          network.unsubscribe(groupId, bob.peerId);
          network.unsubscribe(groupId, charlie.peerId);
          expect(network.isSubscribed(groupId, bob.peerId), isFalse);
          expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

          final removedAt = DateTime.now().toUtc().add(
            const Duration(seconds: 1),
          );
          final readdAt = removedAt.add(const Duration(seconds: 1));
          await alice.removeMember(
            groupId: groupId,
            memberPeerId: charlie.peerId,
            memberUsername: charlie.username,
            removedAt: removedAt,
          );
          await _saveKey(alice, groupId, 2, 'nw003-k2');
          await _saveKey(bob, groupId, 2, 'nw003-k2');

          final (removedResult, removedSent) = await alice
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: removedWindowText,
                messageId: 'nw003-removed-window',
                timestamp: removedAt.add(const Duration(seconds: 1)),
                publishTopicPeersOverride: 0,
              );
          expect(removedResult, SendGroupMessageResult.successNoPeers);
          expect(removedSent, isNotNull);
          expect(removedSent!.inboxStored, isTrue);
          expect(removedSent.keyGeneration, 2);

          final inboxPayload = latestBridgePayload(
            alice.bridge,
            'group:inboxStore',
          );
          expect(inboxPayload['recipientPeerIds'], [bob.peerId]);
          expect(
            inboxPayload['recipientPeerIds'],
            isNot(contains(charlie.peerId)),
          );
          final storedMessage = inboxPayload['message'] as String;

          await alice.addMember(
            groupId: groupId,
            invitee: charlie,
            joinedAt: readdAt,
          );
          await _saveKey(charlie, groupId, 2, 'nw003-k2');

          _addRelayStoredMessagePage(
            receiverBridge: bobBridge,
            groupId: groupId,
            fromPeerId: alice.peerId,
            storedMessage: storedMessage,
          );
          _addRelayStoredMessagePage(
            receiverBridge: charlieBridge,
            groupId: groupId,
            fromPeerId: alice.peerId,
            storedMessage: storedMessage,
          );

          await rejoinGroupTopics(bridge: bob.bridge, groupRepo: bob.groupRepo);
          await drainGroupOfflineInbox(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            msgRepo: bob.msgRepo,
            selfPeerId: bob.peerId,
          );
          await rejoinGroupTopics(
            bridge: charlie.bridge,
            groupRepo: charlie.groupRepo,
          );
          await drainGroupOfflineInbox(
            bridge: charlie.bridge,
            groupRepo: charlie.groupRepo,
            msgRepo: charlie.msgRepo,
            selfPeerId: charlie.peerId,
          );

          network.subscribe(groupId, bob.peerId);
          network.subscribe(groupId, charlie.peerId);
          expect(network.isSubscribed(groupId, bob.peerId), isTrue);
          expect(network.isSubscribed(groupId, charlie.peerId), isTrue);

          await alice.broadcastMemberAdded(
            groupId: groupId,
            newMember: charlie,
            eventAt: readdAt,
          );
          await pumpUntilAsync(() async {
            return await bob.groupRepo.getMember(groupId, charlie.peerId) !=
                null;
          });

          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toList(growable: false);
          final charlieTexts = (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toList(growable: false);
          expect(
            bobTexts.where((text) => text == removedWindowText),
            hasLength(1),
          );
          expect(charlieTexts, isNot(contains(removedWindowText)));

          await alice.sendGroupMessage(
            groupId: groupId,
            text: aliceAfterHeal,
            messageId: 'nw003-alice-live-after-heal',
            timestamp: readdAt.add(const Duration(seconds: 1)),
          );
          await bob.sendGroupMessage(
            groupId: groupId,
            text: bobAfterHeal,
            messageId: 'nw003-bob-live-after-heal',
            timestamp: readdAt.add(const Duration(seconds: 2)),
          );
          await charlie.sendGroupMessage(
            groupId: groupId,
            text: charlieAfterHeal,
            messageId: 'nw003-charlie-live-after-heal',
            timestamp: readdAt.add(const Duration(seconds: 3)),
          );
          await pumpUntilAsync(() async {
            final aliceTexts = (await alice.loadGroupMessages(
              groupId,
            )).map((message) => message.text).toSet();
            final bobTexts = (await bob.loadGroupMessages(
              groupId,
            )).map((message) => message.text).toSet();
            final charlieTexts = (await charlie.loadGroupMessages(
              groupId,
            )).map((message) => message.text).toSet();
            return aliceTexts.containsAll({bobAfterHeal, charlieAfterHeal}) &&
                bobTexts.containsAll({
                  removedWindowText,
                  aliceAfterHeal,
                  charlieAfterHeal,
                }) &&
                charlieTexts.containsAll({aliceAfterHeal, bobAfterHeal}) &&
                !charlieTexts.contains(removedWindowText);
          }, maxPumps: 120);

          final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
          expect(
            (await alice.groupRepo.getMembers(
              groupId,
            )).map((member) => member.peerId).toSet(),
            expectedMembers,
          );
          expect(
            (await bob.groupRepo.getMembers(
              groupId,
            )).map((member) => member.peerId).toSet(),
            expectedMembers,
          );
          expect(
            (await charlie.groupRepo.getMembers(
              groupId,
            )).map((member) => member.peerId).toSet(),
            expectedMembers,
          );
          expect(
            (await alice.groupRepo.getLatestKey(groupId))!.keyGeneration,
            2,
          );
          expect((await bob.groupRepo.getLatestKey(groupId))!.keyGeneration, 2);
          expect(
            (await charlie.groupRepo.getLatestKey(groupId))!.keyGeneration,
            2,
          );

          alice.dispose();
          bob.dispose();
          charlie.dispose();
        },
      );

      test(
        'NW-012 long offline reconnect with multiple epoch changes converges',
        () async {
          final alice = GroupTestUser.create(
            peerId: 'alice-nw012-long-offline-peer',
            username: 'Alice',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'bob-nw012-long-offline-peer',
            username: 'Bob',
            network: network,
          );
          final charlie = GroupTestUser.create(
            peerId: 'charlie-nw012-long-offline-peer',
            username: 'Charlie',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final charlieBridge = charlie.bridge as _CursorInboxBridge;

          const groupId = 'group-nw012-long-offline-epoch-churn';
          const baselineText = 'NW-012 baseline before long offline';
          const removedWindowText = 'NW-012 removed-window while offline';
          const aliceFinalText = 'NW-012 Alice final active interval';
          const bobFinalText = 'NW-012 Bob final active interval';
          const charlieLiveText = 'NW-012 Charlie post reconnect live';

          await alice.createGroup(groupId: groupId, name: 'NW-012 Replay');
          await alice.addMember(groupId: groupId, invitee: bob);
          await alice.addMember(groupId: groupId, invitee: charlie);
          await _saveKey(alice, groupId, 1, 'nw012-k1');
          await _saveKey(bob, groupId, 1, 'nw012-k1');
          await _saveKey(charlie, groupId, 1, 'nw012-k1');

          alice.start();
          bob.start();
          charlie.start();
          await alice.sendGroupMessage(
            groupId: groupId,
            text: baselineText,
            messageId: 'nw012-baseline',
          );
          await pump();
          expect(
            (await charlie.loadGroupMessages(
              groupId,
            )).map((message) => message.text),
            contains(baselineText),
          );

          network.unsubscribe(groupId, charlie.peerId);
          expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

          final baseAt = DateTime.now().toUtc().add(const Duration(seconds: 1));
          final removedAt = baseAt.add(const Duration(seconds: 10));
          final readdedAt = baseAt.add(const Duration(seconds: 20));
          final finalKeyAt = readdedAt.add(const Duration(seconds: 1));

          await alice.removeMember(
            groupId: groupId,
            memberPeerId: charlie.peerId,
            memberUsername: charlie.username,
            removedAt: removedAt,
          );
          await _saveKey(alice, groupId, 2, 'nw012-k2');
          await _saveKey(bob, groupId, 2, 'nw012-k2');

          final (removedResult, removedSent) = await alice
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: removedWindowText,
                messageId: 'nw012-removed-window',
                timestamp: removedAt.add(const Duration(seconds: 1)),
                publishTopicPeersOverride: 0,
              );
          expect(removedResult, SendGroupMessageResult.successNoPeers);
          expect(removedSent, isNotNull);
          expect(removedSent!.inboxStored, isTrue);
          final removedStore = latestBridgePayload(
            alice.bridge,
            'group:inboxStore',
          );
          expect(removedStore['recipientPeerIds'], [bob.peerId]);
          expect(
            removedStore['recipientPeerIds'],
            isNot(contains(charlie.peerId)),
          );

          await alice.addMember(
            groupId: groupId,
            invitee: charlie,
            joinedAt: readdedAt,
          );
          await _saveKey(alice, groupId, 3, 'nw012-k3');
          await _saveKey(bob, groupId, 3, 'nw012-k3');
          await _saveKey(charlie, groupId, 3, 'nw012-k3');
          await alice.broadcastMemberAdded(
            groupId: groupId,
            newMember: charlie,
            eventAt: readdedAt,
          );
          await pumpUntilAsync(() async {
            return await bob.groupRepo.getMember(groupId, charlie.peerId) !=
                null;
          });
          await _saveKey(alice, groupId, 4, 'nw012-k4');
          await _saveKey(bob, groupId, 4, 'nw012-k4');
          await _saveKey(charlie, groupId, 4, 'nw012-k4');

          final (aliceFinalResult, aliceFinalSent) = await alice
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: aliceFinalText,
                messageId: 'nw012-alice-final-active',
                timestamp: finalKeyAt.add(const Duration(seconds: 1)),
                publishTopicPeersOverride: 0,
              );
          expect(aliceFinalResult, SendGroupMessageResult.successNoPeers);
          expect(aliceFinalSent, isNotNull);
          expect(aliceFinalSent!.keyGeneration, 4);
          final aliceFinalStore = latestBridgePayload(
            alice.bridge,
            'group:inboxStore',
          );
          expect(
            (aliceFinalStore['recipientPeerIds'] as List).cast<String>(),
            unorderedEquals(<String>[bob.peerId, charlie.peerId]),
          );

          final (bobFinalResult, bobFinalSent) = await bob
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: bobFinalText,
                messageId: 'nw012-bob-final-active',
                timestamp: finalKeyAt.add(const Duration(seconds: 2)),
                publishTopicPeersOverride: 0,
              );
          expect(bobFinalResult, SendGroupMessageResult.successNoPeers);
          expect(bobFinalSent, isNotNull);
          expect(bobFinalSent!.keyGeneration, 4);
          final bobFinalStore = latestBridgePayload(
            bob.bridge,
            'group:inboxStore',
          );
          expect(
            (bobFinalStore['recipientPeerIds'] as List).cast<String>(),
            unorderedEquals(<String>[alice.peerId, charlie.peerId]),
          );

          Map<String, dynamic> relayMessage({
            required String fromPeerId,
            required Map<String, dynamic> store,
            required DateTime timestamp,
          }) {
            return <String, dynamic>{
              'from': fromPeerId,
              'message': store['message'] as String,
              'timestamp': timestamp.millisecondsSinceEpoch,
            };
          }

          final aliceFinalRelay = relayMessage(
            fromPeerId: alice.peerId,
            store: aliceFinalStore,
            timestamp: finalKeyAt.add(const Duration(seconds: 1)),
          );
          final bobFinalRelay = relayMessage(
            fromPeerId: bob.peerId,
            store: bobFinalStore,
            timestamp: finalKeyAt.add(const Duration(seconds: 2)),
          );
          charlieBridge.addPage(groupId, '', [
            relayMessage(
              fromPeerId: alice.peerId,
              store: removedStore,
              timestamp: removedAt.add(const Duration(seconds: 1)),
            ),
            aliceFinalRelay,
            bobFinalRelay,
            Map<String, dynamic>.from(aliceFinalRelay),
          ], '');

          await rejoinGroupTopics(
            bridge: charlie.bridge,
            groupRepo: charlie.groupRepo,
          );
          final drainResult = await drainGroupOfflineInbox(
            bridge: charlie.bridge,
            groupRepo: charlie.groupRepo,
            msgRepo: charlie.msgRepo,
            selfPeerId: charlie.peerId,
          );
          expect(drainResult.isSuccessful, isTrue);

          network.subscribe(groupId, charlie.peerId);
          expect(network.isSubscribed(groupId, charlie.peerId), isTrue);
          await charlie.sendGroupMessage(
            groupId: groupId,
            text: charlieLiveText,
            messageId: 'nw012-charlie-post-reconnect-live',
            timestamp: finalKeyAt.add(const Duration(seconds: 3)),
          );

          await pumpUntilAsync(() async {
            final aliceTexts = (await alice.loadGroupMessages(
              groupId,
            )).map((message) => message.text).toSet();
            final bobTexts = (await bob.loadGroupMessages(
              groupId,
            )).map((message) => message.text).toSet();
            return aliceTexts.contains(charlieLiveText) &&
                bobTexts.contains(charlieLiveText);
          }, maxPumps: 120);

          final charlieMessages = await charlie.loadGroupMessages(groupId);
          final charlieTexts = charlieMessages
              .map((message) => message.text)
              .toList(growable: false);
          expect(charlieTexts, isNot(contains(removedWindowText)));
          expect(
            charlieTexts.where((text) => text == aliceFinalText),
            hasLength(1),
          );
          expect(
            charlieTexts.where((text) => text == bobFinalText),
            hasLength(1),
          );
          expect(
            charlieTexts.where((text) => text == charlieLiveText),
            hasLength(1),
          );

          final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
          expect(
            (await charlie.groupRepo.getMembers(
              groupId,
            )).map((member) => member.peerId).toSet(),
            expectedMembers,
          );
          expect(
            (await charlie.groupRepo.getMember(
              groupId,
              charlie.peerId,
            ))!.joinedAt,
            readdedAt,
          );
          expect(
            (await charlie.groupRepo.getLatestKey(groupId))!.keyGeneration,
            4,
          );

          alice.dispose();
          bob.dispose();
          charlie.dispose();
        },
      );

      test(
        'GR-015 relay reconnect replays outage messages and resumes live delivery without restart',
        () async {
          final admin = GroupTestUser.create(
            peerId: 'admin-gr015-peer',
            username: 'Alice',
            network: network,
          );
          final onlineReader = GroupTestUser.create(
            peerId: 'reader-gr015-online-peer',
            username: 'Bob',
            network: network,
          );
          final reconnectingReader = GroupTestUser.create(
            peerId: 'reader-gr015-reconnect-peer',
            username: 'Carol',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final reconnectBridge =
              reconnectingReader.bridge as _CursorInboxBridge;

          const groupId = 'group-gr015-relay-reconnect';
          await admin.createGroup(groupId: groupId, name: 'GR015 Relay');
          await admin.addMember(groupId: groupId, invitee: onlineReader);
          await admin.addMember(groupId: groupId, invitee: reconnectingReader);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(onlineReader, groupId, 1, 'k1');
          await _saveKey(reconnectingReader, groupId, 1, 'k1');

          admin.start();
          onlineReader.start();
          reconnectingReader.start();

          Future<List<String>> incomingTexts(GroupTestUser user) async {
            return (await user.loadGroupMessages(groupId))
                .where((message) => message.isIncoming)
                .map((message) => message.text)
                .toList(growable: false);
          }

          await admin.sendGroupMessage(
            groupId: groupId,
            text: 'Before relay drop',
          );
          await pumpUntilAsync(() async {
            return (await incomingTexts(reconnectingReader)).length == 1;
          }, maxPumps: 120);
          expect(await incomingTexts(onlineReader), ['Before relay drop']);
          expect(await incomingTexts(reconnectingReader), [
            'Before relay drop',
          ]);

          network.unsubscribe(groupId, reconnectingReader.peerId);
          expect(
            network.isSubscribed(groupId, reconnectingReader.peerId),
            isFalse,
          );

          final (firstResult, firstSent) = await admin
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: 'During relay drop 1',
              );
          final (secondResult, secondSent) = await admin
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: 'During relay drop 2',
              );
          expect(firstResult, SendGroupMessageResult.success);
          expect(firstSent, isNotNull);
          expect(firstSent!.inboxStored, isTrue);
          expect(secondResult, SendGroupMessageResult.success);
          expect(secondSent, isNotNull);
          expect(secondSent!.inboxStored, isTrue);

          await pumpUntilAsync(() async {
            return (await incomingTexts(onlineReader)).length == 3;
          }, maxPumps: 120);
          expect(await incomingTexts(onlineReader), [
            'Before relay drop',
            'During relay drop 1',
            'During relay drop 2',
          ]);
          expect(await incomingTexts(reconnectingReader), [
            'Before relay drop',
          ]);

          final inboxStores = bridgePayloads(admin.bridge, 'group:inboxStore');
          expect(inboxStores, hasLength(2));
          for (final payload in inboxStores) {
            expect(
              (payload['recipientPeerIds'] as List<dynamic>).cast<String>(),
              contains(reconnectingReader.peerId),
            );
          }

          _addRelayStoredMessagePage(
            receiverBridge: reconnectBridge,
            groupId: groupId,
            fromPeerId: admin.peerId,
            storedMessage: inboxStores[0]['message'] as String,
            nextCursor: 'cursor-gr015-reconnect-2',
          );
          _addRelayStoredMessagePage(
            receiverBridge: reconnectBridge,
            groupId: groupId,
            fromPeerId: admin.peerId,
            storedMessage: inboxStores[1]['message'] as String,
            cursor: 'cursor-gr015-reconnect-2',
          );

          network.subscribe(groupId, reconnectingReader.peerId);
          expect(
            network.isSubscribed(groupId, reconnectingReader.peerId),
            isTrue,
          );
          await drainGroupOfflineInbox(
            bridge: reconnectingReader.bridge,
            groupRepo: reconnectingReader.groupRepo,
            msgRepo: reconnectingReader.msgRepo,
          );

          expect(await incomingTexts(reconnectingReader), [
            'Before relay drop',
            'During relay drop 1',
            'During relay drop 2',
          ]);

          await admin.sendGroupMessage(
            groupId: groupId,
            text: 'After relay reconnect',
          );
          await pumpUntilAsync(() async {
            return (await incomingTexts(reconnectingReader)).length == 4;
          }, maxPumps: 120);

          expect(await incomingTexts(onlineReader), [
            'Before relay drop',
            'During relay drop 1',
            'During relay drop 2',
            'After relay reconnect',
          ]);
          expect(await incomingTexts(reconnectingReader), [
            'Before relay drop',
            'During relay drop 1',
            'During relay drop 2',
            'After relay reconnect',
          ]);

          final cursorCmds = reconnectBridge.sentMessages
              .map((message) => jsonDecode(message) as Map<String, dynamic>)
              .where((message) => message['cmd'] == 'group:inboxRetrieveCursor')
              .toList(growable: false);
          expect(cursorCmds, hasLength(2));
          expect(cursorCmds[0]['payload']['cursor'], '');
          expect(
            cursorCmds[1]['payload']['cursor'],
            'cursor-gr015-reconnect-2',
          );

          admin.dispose();
          onlineReader.dispose();
          reconnectingReader.dispose();
        },
      );

      test(
        'GR-016 watchdog restart rejoins every private group and resumes delivery',
        () async {
          final admin = GroupTestUser.create(
            peerId: 'admin-gr016-peer',
            username: 'Alice',
            network: network,
          );
          final onlineReader = GroupTestUser.create(
            peerId: 'reader-gr016-online-peer',
            username: 'Carol',
            network: network,
          );
          final recoveringReader = GroupTestUser.create(
            peerId: 'reader-gr016-recover-peer',
            username: 'Bob',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final recoverBridge = recoveringReader.bridge as _CursorInboxBridge;

          const groupIds = ['group-gr016-alpha', 'group-gr016-beta'];
          const labelsByGroup = {
            'group-gr016-alpha': 'Alpha',
            'group-gr016-beta': 'Beta',
          };

          for (final groupId in groupIds) {
            final label = labelsByGroup[groupId]!;
            await admin.createGroup(groupId: groupId, name: 'GR016 $label');
            await admin.addMember(groupId: groupId, invitee: onlineReader);
            await admin.addMember(groupId: groupId, invitee: recoveringReader);
            await _saveKey(admin, groupId, 1, 'key-$label');
            await _saveKey(onlineReader, groupId, 1, 'key-$label');
            await _saveKey(recoveringReader, groupId, 1, 'key-$label');
          }

          admin.start();
          onlineReader.start();
          recoveringReader.start();

          Future<List<String>> incomingTexts(
            GroupTestUser user,
            String groupId,
          ) async {
            return (await user.loadGroupMessages(groupId))
                .where((message) => message.isIncoming)
                .map((message) => message.text)
                .toList(growable: false);
          }

          for (final groupId in groupIds) {
            final label = labelsByGroup[groupId]!;
            await admin.sendGroupMessage(
              groupId: groupId,
              text: 'Before watchdog $label',
            );
          }
          await pumpUntilAsync(() async {
            for (final groupId in groupIds) {
              if ((await incomingTexts(recoveringReader, groupId)).length !=
                  1) {
                return false;
              }
            }
            return true;
          }, maxPumps: 120);

          for (final groupId in groupIds) {
            final label = labelsByGroup[groupId]!;
            expect(await incomingTexts(onlineReader, groupId), [
              'Before watchdog $label',
            ]);
            expect(await incomingTexts(recoveringReader, groupId), [
              'Before watchdog $label',
            ]);
          }

          for (final groupId in groupIds) {
            network.unsubscribe(groupId, recoveringReader.peerId);
            expect(
              network.isSubscribed(groupId, recoveringReader.peerId),
              isFalse,
              reason: 'Watchdog restart drops runtime topic state for $groupId',
            );
          }

          for (final groupId in groupIds) {
            final label = labelsByGroup[groupId]!;
            final (result, sent) = await admin.sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'During watchdog $label',
              messageId: 'gr016-during-${label.toLowerCase()}',
            );
            expect(result, SendGroupMessageResult.success);
            expect(sent, isNotNull);
            expect(sent!.inboxStored, isTrue);
          }

          await pumpUntilAsync(() async {
            for (final groupId in groupIds) {
              if ((await incomingTexts(onlineReader, groupId)).length != 2) {
                return false;
              }
            }
            return true;
          }, maxPumps: 120);

          for (final groupId in groupIds) {
            final label = labelsByGroup[groupId]!;
            expect(await incomingTexts(onlineReader, groupId), [
              'Before watchdog $label',
              'During watchdog $label',
            ]);
            expect(await incomingTexts(recoveringReader, groupId), [
              'Before watchdog $label',
            ]);
          }

          final inboxStores = bridgePayloads(admin.bridge, 'group:inboxStore');
          expect(inboxStores, hasLength(groupIds.length));
          for (final groupId in groupIds) {
            final matchingStores = inboxStores
                .where((payload) => payload['groupId'] == groupId)
                .toList(growable: false);
            expect(matchingStores, hasLength(1));
            expect(
              (matchingStores.single['recipientPeerIds'] as List<dynamic>)
                  .cast<String>(),
              contains(recoveringReader.peerId),
            );
            _addRelayStoredMessagePage(
              receiverBridge: recoverBridge,
              groupId: groupId,
              fromPeerId: admin.peerId,
              storedMessage: matchingStores.single['message'] as String,
            );
          }

          final rejoinResult = await rejoinGroupTopics(
            bridge: recoveringReader.bridge,
            groupRepo: recoveringReader.groupRepo,
            reason: RejoinReason.watchdogRestart,
          );
          expect(rejoinResult.joinedGroupCount, groupIds.length);
          expect(rejoinResult.skippedNoKeyCount, 0);
          expect(rejoinResult.errorCount, 0);
          expect(rejoinResult.canAcknowledgeGroupRecovery, isTrue);

          final joinCmds = recoverBridge.sentMessages
              .map((message) => jsonDecode(message) as Map<String, dynamic>)
              .where((message) => message['cmd'] == 'group:join')
              .toList(growable: false);
          expect(joinCmds, hasLength(groupIds.length));
          final joinedGroupIds = joinCmds
              .map((message) => message['payload']['groupId'] as String)
              .toSet();
          expect(joinedGroupIds, groupIds.toSet());

          for (final command in joinCmds) {
            final payload = command['payload'] as Map<String, dynamic>;
            final groupId = payload['groupId'] as String;
            final label = labelsByGroup[groupId]!;
            expect(payload['groupKey'], 'key-$label');
            expect(payload['keyEpoch'], 1);
          }

          for (final groupId in groupIds) {
            network.subscribe(groupId, recoveringReader.peerId);
            expect(
              network.isSubscribed(groupId, recoveringReader.peerId),
              isTrue,
            );
          }
          await drainGroupOfflineInbox(
            bridge: recoveringReader.bridge,
            groupRepo: recoveringReader.groupRepo,
            msgRepo: recoveringReader.msgRepo,
          );

          for (final groupId in groupIds) {
            final label = labelsByGroup[groupId]!;
            expect(await incomingTexts(recoveringReader, groupId), [
              'Before watchdog $label',
              'During watchdog $label',
            ]);
          }

          for (final groupId in groupIds) {
            final label = labelsByGroup[groupId]!;
            await admin.sendGroupMessage(
              groupId: groupId,
              text: 'After watchdog $label',
            );
          }
          await pumpUntilAsync(() async {
            for (final groupId in groupIds) {
              if ((await incomingTexts(recoveringReader, groupId)).length !=
                  3) {
                return false;
              }
            }
            return true;
          }, maxPumps: 120);

          for (final groupId in groupIds) {
            final label = labelsByGroup[groupId]!;
            final expected = [
              'Before watchdog $label',
              'During watchdog $label',
              'After watchdog $label',
            ];
            expect(await incomingTexts(onlineReader, groupId), expected);
            expect(await incomingTexts(recoveringReader, groupId), expected);
          }

          final cursorCmds = recoverBridge.sentMessages
              .map((message) => jsonDecode(message) as Map<String, dynamic>)
              .where((message) => message['cmd'] == 'group:inboxRetrieveCursor')
              .toList(growable: false);
          expect(cursorCmds, hasLength(groupIds.length));
          expect(
            cursorCmds
                .map((message) => message['payload']['groupId'] as String)
                .toSet(),
            groupIds.toSet(),
          );
          expect(
            cursorCmds.map((message) => message['payload']['cursor'] as String),
            everyElement(''),
          );

          admin.dispose();
          onlineReader.dispose();
          recoveringReader.dispose();
        },
      );

      test(
        'NW-004 relay reconnect repairs dropped group topic subscriptions and drains replay',
        () async {
          final trace = <String>[];
          final bobBridge = _RejoiningCursorInboxBridge(
            network: network,
            peerId: 'bob-nw004-reconnect-peer',
            trace: trace,
          );
          final alice = GroupTestUser.create(
            peerId: 'alice-nw004-reconnect-peer',
            username: 'Alice',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'bob-nw004-reconnect-peer',
            username: 'Bob',
            network: network,
            bridge: bobBridge,
          );
          final charlie = GroupTestUser.create(
            peerId: 'charlie-nw004-reconnect-peer',
            username: 'Charlie',
            network: network,
          );
          const groupIds = <String>[
            'nw004-reconnect-alpha',
            'nw004-reconnect-beta',
          ];

          Future<Set<String>> incomingTexts(
            GroupTestUser user,
            String groupId,
          ) async {
            return (await user.loadGroupMessages(groupId))
                .where((message) => message.isIncoming)
                .map((message) => message.text)
                .toSet();
          }

          try {
            for (final groupId in groupIds) {
              await alice.createGroup(groupId: groupId, name: groupId);
              await alice.addMember(groupId: groupId, invitee: bob);
              await alice.addMember(groupId: groupId, invitee: charlie);
              await _saveKey(alice, groupId, 1, 'nw004-$groupId-key');
              await _saveKey(bob, groupId, 1, 'nw004-$groupId-key');
              await _saveKey(charlie, groupId, 1, 'nw004-$groupId-key');
            }

            alice.start();
            bob.start();
            charlie.start();

            for (final groupId in groupIds) {
              await alice.sendGroupMessage(
                groupId: groupId,
                text: 'NW-004 baseline $groupId',
                messageId: 'nw004-baseline-$groupId',
              );
            }
            await pumpUntilAsync(() async {
              for (final groupId in groupIds) {
                if (!(await incomingTexts(
                  bob,
                  groupId,
                )).contains('NW-004 baseline $groupId')) {
                  return false;
                }
              }
              return true;
            }, maxPumps: 80);

            final membersBefore = <String, Set<String>>{};
            final epochBefore = <String, int>{};
            for (final groupId in groupIds) {
              membersBefore[groupId] = (await bob.groupRepo.getMembers(
                groupId,
              )).map((member) => member.peerId).toSet();
              epochBefore[groupId] = (await bob.groupRepo.getLatestKey(
                groupId,
              ))!.keyGeneration;
              network.unsubscribe(groupId, bob.peerId);
              expect(network.isSubscribed(groupId, bob.peerId), isFalse);
            }

            for (final groupId in groupIds) {
              final (result, sent) = await alice.sendGroupMessageViaBridge(
                groupId: groupId,
                text: 'NW-004 missed during relay drop $groupId',
                messageId: 'nw004-missed-$groupId',
                publishTopicPeersOverride: 0,
              );
              expect(result, SendGroupMessageResult.successNoPeers);
              expect(sent, isNotNull);
              expect(sent!.inboxStored, isTrue);
              _injectInboxMessageFromLatestStore(
                senderBridge: alice.bridge,
                receiverBridge: bobBridge,
                receiverPeerId: bob.peerId,
                groupId: groupId,
              );
            }
            await pump();
            for (final groupId in groupIds) {
              expect(
                await incomingTexts(bob, groupId),
                isNot(contains('NW-004 missed during relay drop $groupId')),
                reason: 'Bob must not receive the dropped publish live',
              );
            }

            final rejoinResult = await rejoinGroupTopics(
              bridge: bob.bridge,
              groupRepo: bob.groupRepo,
              reason: RejoinReason.nodeRequestedRecovery,
            );
            expect(rejoinResult.errorCount, 0);
            final drainResult = await drainGroupOfflineInbox(
              bridge: bob.bridge,
              groupRepo: bob.groupRepo,
              msgRepo: bob.msgRepo,
              groupMessageListener: bob.groupMessageListener,
              selfPeerId: bob.peerId,
            );
            expect(drainResult.isSuccessful, isTrue);
            await callGroupAcknowledgeRecovery(bob.bridge);

            final ackIndex = trace.indexOf('ack');
            expect(ackIndex, isNot(-1));
            for (final groupId in groupIds) {
              expect(
                trace.indexOf('join:$groupId'),
                inInclusiveRange(0, ackIndex - 1),
              );
              expect(
                trace.indexOf('drain:$groupId'),
                inInclusiveRange(0, ackIndex - 1),
              );
              expect(network.isSubscribed(groupId, bob.peerId), isTrue);
              final missed = 'NW-004 missed during relay drop $groupId';
              final bobMessages = await bob.loadGroupMessages(groupId);
              expect(
                bobMessages.where(
                  (message) => message.text == missed && message.isIncoming,
                ),
                hasLength(1),
              );
              expect(
                (await bob.groupRepo.getMembers(
                  groupId,
                )).map((member) => member.peerId).toSet(),
                membersBefore[groupId],
              );
              expect(
                (await bob.groupRepo.getLatestKey(groupId))!.keyGeneration,
                epochBefore[groupId],
              );
            }

            for (final groupId in groupIds) {
              await alice.sendGroupMessage(
                groupId: groupId,
                text: 'NW-004 live after reconnect $groupId',
                messageId: 'nw004-live-after-reconnect-$groupId',
              );
            }
            await pumpUntilAsync(() async {
              for (final groupId in groupIds) {
                if (!(await incomingTexts(
                  bob,
                  groupId,
                )).contains('NW-004 live after reconnect $groupId')) {
                  return false;
                }
              }
              return true;
            }, maxPumps: 80);

            for (final groupId in groupIds) {
              await bob.sendGroupMessage(
                groupId: groupId,
                text: 'NW-004 bob publish after reconnect $groupId',
                messageId: 'nw004-bob-after-reconnect-$groupId',
              );
            }
            await pumpUntilAsync(() async {
              for (final groupId in groupIds) {
                final bobPublish =
                    'NW-004 bob publish after reconnect $groupId';
                final aliceTexts = await incomingTexts(alice, groupId);
                final charlieTexts = await incomingTexts(charlie, groupId);
                if (!aliceTexts.contains(bobPublish) ||
                    !charlieTexts.contains(bobPublish)) {
                  return false;
                }
              }
              return true;
            }, maxPumps: 80);
          } finally {
            alice.dispose();
            bob.dispose();
            charlie.dispose();
          }
        },
      );

      test(
        'NW-005 stale and fresh rediscovery subscribers do not change membership truth',
        () async {
          final alice = GroupTestUser.create(
            peerId: 'alice-nw005-discovery-peer',
            username: 'Alice',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'bob-nw005-discovery-peer',
            username: 'Bob',
            network: network,
          );
          final charlie = GroupTestUser.create(
            peerId: 'charlie-nw005-discovery-peer',
            username: 'Charlie',
            network: network,
          );
          final dana = GroupTestUser.create(
            peerId: 'dana-nw005-outsider-peer',
            username: 'Dana',
            network: network,
          );
          const groupId = 'group-nw005-rendezvous-truth';
          const removedWindowText = 'NW-005 removed-window while rediscovered';
          const postReaddText = 'NW-005 post-readd after fresh rediscovery';

          Future<Set<String>> incomingTexts(GroupTestUser user) async {
            return (await user.loadGroupMessages(groupId))
                .where((message) => message.isIncoming)
                .map((message) => message.text)
                .toSet();
          }

          Future<Set<String>> memberPeerIds(GroupTestUser user) async {
            return (await user.groupRepo.getMembers(
              groupId,
            )).map((member) => member.peerId).toSet();
          }

          try {
            final createdAt = DateTime.now().toUtc();
            await alice.createGroup(
              groupId: groupId,
              name: 'NW-005',
              createdAt: createdAt,
            );
            await alice.addMember(
              groupId: groupId,
              invitee: bob,
              joinedAt: createdAt.add(const Duration(seconds: 1)),
            );
            await alice.addMember(
              groupId: groupId,
              invitee: charlie,
              joinedAt: createdAt.add(const Duration(seconds: 2)),
            );
            await _saveKey(alice, groupId, 1, 'nw005-epoch-1');
            await _saveKey(bob, groupId, 1, 'nw005-epoch-1');
            await _saveKey(charlie, groupId, 1, 'nw005-epoch-1');

            alice.start();
            bob.start();
            charlie.start();
            dana.start();

            await alice.broadcastMemberAdded(
              groupId: groupId,
              newMember: charlie,
              eventAt: createdAt.add(const Duration(seconds: 2)),
            );
            await pumpUntilAsync(() async {
              return (await memberPeerIds(bob)).contains(charlie.peerId);
            }, maxPumps: 80);

            final removedAt = createdAt.add(const Duration(minutes: 1));
            await alice.removeMember(
              groupId: groupId,
              memberPeerId: charlie.peerId,
              memberUsername: charlie.username,
              removedAt: removedAt,
            );
            await pumpUntilAsync(() async {
              return !(await memberPeerIds(bob)).contains(charlie.peerId);
            }, maxPumps: 80);
            await _saveKey(alice, groupId, 2, 'nw005-epoch-2');
            await _saveKey(bob, groupId, 2, 'nw005-epoch-2');

            // Simulate rendezvous returning stale Charlie and a fresh unknown
            // peer. Connectivity changes, but app membership stays Alice/Bob.
            network.subscribe(groupId, charlie.peerId);
            network.subscribe(groupId, dana.peerId);
            expect(network.getSubscribers(groupId), contains(charlie.peerId));
            expect(network.getSubscribers(groupId), contains(dana.peerId));

            final (removedResult, removedMessage) = await alice
                .sendGroupMessageViaBridge(
                  groupId: groupId,
                  text: removedWindowText,
                  messageId: 'nw005-removed-window',
                  timestamp: removedAt.add(const Duration(seconds: 1)),
                );
            expect(removedResult, SendGroupMessageResult.success);
            expect(removedMessage, isNotNull);

            await pumpUntilAsync(() async {
              return (await incomingTexts(bob)).contains(removedWindowText);
            }, maxPumps: 80);
            await pump();

            final removedStore = latestBridgePayload(
              alice.bridge,
              'group:inboxStore',
            );
            final removedRecipients =
                (removedStore['recipientPeerIds'] as List<dynamic>)
                    .cast<String>();
            expect(removedRecipients, [bob.peerId]);
            expect(
              await incomingTexts(charlie),
              isNot(contains(removedWindowText)),
            );
            expect(
              await incomingTexts(dana),
              isNot(contains(removedWindowText)),
            );
            expect(await memberPeerIds(alice), {alice.peerId, bob.peerId});
            expect(await memberPeerIds(bob), {alice.peerId, bob.peerId});

            final readdAt = removedAt.add(const Duration(minutes: 1));
            await alice.addMember(
              groupId: groupId,
              invitee: charlie,
              joinedAt: readdAt,
            );
            await _saveKey(alice, groupId, 3, 'nw005-epoch-3');
            await _saveKey(bob, groupId, 3, 'nw005-epoch-3');
            await _saveKey(charlie, groupId, 3, 'nw005-epoch-3');
            await alice.broadcastMemberAdded(
              groupId: groupId,
              newMember: charlie,
              eventAt: readdAt,
            );
            await pumpUntilAsync(() async {
              return (await memberPeerIds(bob)).contains(charlie.peerId) &&
                  (await memberPeerIds(charlie)).contains(charlie.peerId);
            }, maxPumps: 80);

            // Dana remains connected as rediscovery noise after the fresh
            // member list converges.
            expect(network.getSubscribers(groupId), contains(dana.peerId));

            final (postResult, postMessage) = await alice
                .sendGroupMessageViaBridge(
                  groupId: groupId,
                  text: postReaddText,
                  messageId: 'nw005-post-readd',
                  timestamp: readdAt.add(const Duration(seconds: 1)),
                );
            expect(postResult, SendGroupMessageResult.success);
            expect(postMessage, isNotNull);

            await pumpUntilAsync(() async {
              return (await incomingTexts(bob)).contains(postReaddText) &&
                  (await incomingTexts(charlie)).contains(postReaddText);
            }, maxPumps: 120);
            await pump();

            final postStore = latestBridgePayload(
              alice.bridge,
              'group:inboxStore',
            );
            final postRecipients =
                (postStore['recipientPeerIds'] as List<dynamic>).cast<String>();
            expect(postRecipients.toSet(), {bob.peerId, charlie.peerId});
            expect(postRecipients, isNot(contains(dana.peerId)));
            expect(await incomingTexts(dana), isNot(contains(postReaddText)));

            final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
            expect(await memberPeerIds(alice), expectedMembers);
            expect(await memberPeerIds(bob), expectedMembers);
            expect(await memberPeerIds(charlie), expectedMembers);
          } finally {
            alice.dispose();
            bob.dispose();
            charlie.dispose();
            dana.dispose();
          }
        },
      );

      test(
        'NW-006 peer disconnect does not remove group membership and replay restores the missed message once',
        () async {
          final trace = <String>[];
          final bobBridge = _RejoiningCursorInboxBridge(
            network: network,
            peerId: 'bob-nw006-disconnect-peer',
            trace: trace,
          );
          final alice = GroupTestUser.create(
            peerId: 'alice-nw006-disconnect-peer',
            username: 'Alice',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'bob-nw006-disconnect-peer',
            username: 'Bob',
            network: network,
            bridge: bobBridge,
          );
          final charlie = GroupTestUser.create(
            peerId: 'charlie-nw006-disconnect-peer',
            username: 'Charlie',
            network: network,
          );
          const groupId = 'group-nw006-peer-disconnect-not-removal';
          const baselineText = 'NW-006 baseline before disconnect';
          const missedText = 'NW-006 missed while Bob disconnected';
          const postReconnectText = 'NW-006 Alice live after reconnect';
          const bobPublishText = 'NW-006 Bob publish back after reconnect';

          Future<Set<String>> incomingTexts(GroupTestUser user) async {
            return (await user.loadGroupMessages(groupId))
                .where((message) => message.isIncoming)
                .map((message) => message.text)
                .toSet();
          }

          Future<Set<String>> memberPeerIds(GroupTestUser user) async {
            return (await user.groupRepo.getMembers(
              groupId,
            )).map((member) => member.peerId).toSet();
          }

          bool hasRemovalSignal(List<GroupMessage> messages) {
            return messages.any(
              (message) =>
                  message.text.contains('member_removed') ||
                  message.text.contains('removed'),
            );
          }

          try {
            await alice.createGroup(groupId: groupId, name: 'NW-006');
            await alice.addMember(groupId: groupId, invitee: bob);
            await alice.addMember(groupId: groupId, invitee: charlie);
            await _saveKey(alice, groupId, 1, 'nw006-key');
            await _saveKey(bob, groupId, 1, 'nw006-key');
            await _saveKey(charlie, groupId, 1, 'nw006-key');

            alice.start();
            bob.start();
            charlie.start();

            await alice.broadcastMemberAdded(
              groupId: groupId,
              newMember: charlie,
            );
            await pumpUntilAsync(() async {
              return (await memberPeerIds(bob)).contains(charlie.peerId);
            }, maxPumps: 80);

            await alice.sendGroupMessage(
              groupId: groupId,
              text: baselineText,
              messageId: 'nw006-baseline',
            );
            await pumpUntilAsync(() async {
              return (await incomingTexts(bob)).contains(baselineText) &&
                  (await incomingTexts(charlie)).contains(baselineText);
            }, maxPumps: 80);

            final membersBefore = await memberPeerIds(bob);
            final epochBefore = (await bob.groupRepo.getLatestKey(
              groupId,
            ))!.keyGeneration;
            network.unsubscribe(groupId, bob.peerId);
            expect(network.isSubscribed(groupId, bob.peerId), isFalse);

            final (missedResult, missedSent) = await alice
                .sendGroupMessageViaBridge(
                  groupId: groupId,
                  text: missedText,
                  messageId: 'nw006-missed-during-disconnect',
                );
            expect(missedResult, SendGroupMessageResult.success);
            expect(missedSent, isNotNull);
            expect(missedSent!.inboxStored, isTrue);

            await pumpUntilAsync(() async {
              return (await incomingTexts(charlie)).contains(missedText);
            }, maxPumps: 80);
            expect(
              await incomingTexts(bob),
              isNot(contains(missedText)),
              reason: 'Bob must miss live delivery while unsubscribed',
            );

            final inboxPayload = latestBridgePayload(
              alice.bridge,
              'group:inboxStore',
            );
            final recipientPeerIds =
                (inboxPayload['recipientPeerIds'] as List<dynamic>)
                    .cast<String>();
            expect(recipientPeerIds, contains(bob.peerId));
            expect(recipientPeerIds, contains(charlie.peerId));
            expect(recipientPeerIds, isNot(contains(alice.peerId)));

            _injectInboxMessageFromLatestStore(
              senderBridge: alice.bridge,
              receiverBridge: bobBridge,
              receiverPeerId: bob.peerId,
              groupId: groupId,
            );
            final rejoinResult = await rejoinGroupTopics(
              bridge: bob.bridge,
              groupRepo: bob.groupRepo,
              reason: RejoinReason.nodeRequestedRecovery,
            );
            expect(rejoinResult.errorCount, 0);
            final drainResult = await drainGroupOfflineInbox(
              bridge: bob.bridge,
              groupRepo: bob.groupRepo,
              msgRepo: bob.msgRepo,
              groupMessageListener: bob.groupMessageListener,
              selfPeerId: bob.peerId,
            );
            expect(drainResult.isSuccessful, isTrue);
            expect(network.isSubscribed(groupId, bob.peerId), isTrue);

            final bobMessagesAfterDrain = await bob.loadGroupMessages(groupId);
            expect(
              bobMessagesAfterDrain.where(
                (message) => message.text == missedText && message.isIncoming,
              ),
              hasLength(1),
            );
            expect(trace, contains('join:$groupId'));
            expect(trace, contains('drain:$groupId'));

            await alice.sendGroupMessage(
              groupId: groupId,
              text: postReconnectText,
              messageId: 'nw006-alice-live-after-reconnect',
            );
            await bob.sendGroupMessage(
              groupId: groupId,
              text: bobPublishText,
              messageId: 'nw006-bob-publish-after-reconnect',
            );
            await pumpUntilAsync(() async {
              final aliceTexts = await incomingTexts(alice);
              final bobTexts = await incomingTexts(bob);
              final charlieTexts = await incomingTexts(charlie);
              return bobTexts.contains(postReconnectText) &&
                  aliceTexts.contains(bobPublishText) &&
                  charlieTexts.contains(postReconnectText) &&
                  charlieTexts.contains(bobPublishText);
            }, maxPumps: 120);

            final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
            expect(await memberPeerIds(alice), expectedMembers);
            expect(await memberPeerIds(bob), membersBefore);
            expect(await memberPeerIds(bob), expectedMembers);
            expect(await memberPeerIds(charlie), expectedMembers);
            expect(
              (await bob.groupRepo.getLatestKey(groupId))!.keyGeneration,
              epochBefore,
            );
            expect(
              hasRemovalSignal(await alice.loadGroupMessages(groupId)),
              isFalse,
            );
            expect(
              hasRemovalSignal(await bob.loadGroupMessages(groupId)),
              isFalse,
            );
            expect(
              hasRemovalSignal(await charlie.loadGroupMessages(groupId)),
              isFalse,
            );
          } finally {
            alice.dispose();
            bob.dispose();
            charlie.dispose();
          }
        },
      );

      test(
        'NW-009 relay probe failure keeps membership and replay recovery active',
        () async {
          final trace = <String>[];
          final bobBridge = _RejoiningCursorInboxBridge(
            network: network,
            peerId: 'bob-nw009-probe-peer',
            trace: trace,
          );
          final alice = GroupTestUser.create(
            peerId: 'alice-nw009-probe-peer',
            username: 'Alice',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'bob-nw009-probe-peer',
            username: 'Bob',
            network: network,
            bridge: bobBridge,
          );
          final charlie = GroupTestUser.create(
            peerId: 'charlie-nw009-probe-peer',
            username: 'Charlie',
            network: network,
          );
          const groupId = 'group-nw009-relay-probe-failure';
          const missedText = 'NW-009 missed while relay probe failed';
          const postReturnText = 'NW-009 Alice live after Bob return';
          const bobPublishText = 'NW-009 Bob publish after probe failure';
          const messageId = 'nw009-relay-probe-failed-message';

          Future<Set<String>> incomingTexts(GroupTestUser user) async {
            return (await user.loadGroupMessages(groupId))
                .where((message) => message.isIncoming)
                .map((message) => message.text)
                .toSet();
          }

          Future<Set<String>> memberPeerIds(GroupTestUser user) async {
            return (await user.groupRepo.getMembers(
              groupId,
            )).map((member) => member.peerId).toSet();
          }

          bool hasRemovalSignal(List<GroupMessage> messages) {
            return messages.any(
              (message) =>
                  message.text.contains('member_removed') ||
                  message.text.contains('removed'),
            );
          }

          try {
            await alice.createGroup(groupId: groupId, name: 'NW-009');
            await alice.addMember(groupId: groupId, invitee: bob);
            await alice.addMember(groupId: groupId, invitee: charlie);
            await _saveKey(alice, groupId, 9, 'nw009-key');
            await _saveKey(bob, groupId, 9, 'nw009-key');
            await _saveKey(charlie, groupId, 9, 'nw009-key');

            alice.start();
            bob.start();
            charlie.start();

            await alice.broadcastMemberAdded(
              groupId: groupId,
              newMember: charlie,
            );
            final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
            await pumpUntilAsync(() async {
              return (await memberPeerIds(bob)).containsAll(expectedMembers);
            }, maxPumps: 80);

            alice.bridge.responses['relay:probe'] = {
              'ok': false,
              'errorCode': 'NO_RESERVATION',
              'errorMessage': 'simulated no relay reservation for Bob',
            };
            final probeResult = await callP2PRelayProbe(
              alice.bridge,
              peerId: bob.peerId,
            );
            expect(probeResult['ok'], isFalse);
            expect(probeResult['errorCode'], 'NO_RESERVATION');

            final aliceMembersBefore = await memberPeerIds(alice);
            final bobMembersBefore = await memberPeerIds(bob);
            final charlieMembersBefore = await memberPeerIds(charlie);

            network.unsubscribe(groupId, bob.peerId);
            expect(network.isSubscribed(groupId, bob.peerId), isFalse);

            final (result, sent) = await alice.sendGroupMessageViaBridge(
              groupId: groupId,
              text: missedText,
              messageId: messageId,
              publishTopicPeersOverride: 1,
            );
            expect(result, SendGroupMessageResult.success);
            expect(sent, isNotNull);
            expect(sent!.status, 'sent');
            expect(sent.inboxStored, isTrue);

            await pumpUntilAsync(() async {
              return (await incomingTexts(charlie)).contains(missedText);
            }, maxPumps: 80);
            expect(
              await incomingTexts(bob),
              isNot(contains(missedText)),
              reason: 'Bob must miss live delivery while unsubscribed',
            );

            final inboxPayload = latestBridgePayload(
              alice.bridge,
              'group:inboxStore',
            );
            expect(
              (inboxPayload['recipientPeerIds'] as List<dynamic>)
                  .cast<String>(),
              unorderedEquals([bob.peerId, charlie.peerId]),
            );
            expect(await memberPeerIds(alice), aliceMembersBefore);
            expect(await memberPeerIds(bob), bobMembersBefore);
            expect(await memberPeerIds(charlie), charlieMembersBefore);

            _injectInboxMessageFromLatestStore(
              senderBridge: alice.bridge,
              receiverBridge: bobBridge,
              receiverPeerId: bob.peerId,
              groupId: groupId,
            );
            final rejoinResult = await rejoinGroupTopics(
              bridge: bob.bridge,
              groupRepo: bob.groupRepo,
              reason: RejoinReason.nodeRequestedRecovery,
            );
            expect(rejoinResult.errorCount, 0);
            final drainResult = await drainGroupOfflineInbox(
              bridge: bob.bridge,
              groupRepo: bob.groupRepo,
              msgRepo: bob.msgRepo,
              groupMessageListener: bob.groupMessageListener,
              selfPeerId: bob.peerId,
            );
            expect(drainResult.isSuccessful, isTrue);
            expect(network.isSubscribed(groupId, bob.peerId), isTrue);

            final bobRowsAfterDrain = await bob.loadGroupMessages(groupId);
            expect(
              bobRowsAfterDrain.where(
                (message) => message.text == missedText && message.isIncoming,
              ),
              hasLength(1),
            );
            expect(trace, contains('join:$groupId'));
            expect(trace, contains('drain:$groupId'));

            await alice.sendGroupMessage(
              groupId: groupId,
              text: postReturnText,
              messageId: 'nw009-alice-live-after-return',
            );
            await bob.sendGroupMessage(
              groupId: groupId,
              text: bobPublishText,
              messageId: 'nw009-bob-publish-after-return',
            );
            await pumpUntilAsync(() async {
              return (await incomingTexts(bob)).contains(postReturnText) &&
                  (await incomingTexts(alice)).contains(bobPublishText) &&
                  (await incomingTexts(charlie)).contains(bobPublishText);
            }, maxPumps: 120);

            expect(await memberPeerIds(alice), expectedMembers);
            expect(await memberPeerIds(bob), expectedMembers);
            expect(await memberPeerIds(charlie), expectedMembers);
            expect(
              hasRemovalSignal(await alice.loadGroupMessages(groupId)),
              isFalse,
            );
            expect(
              hasRemovalSignal(await bob.loadGroupMessages(groupId)),
              isFalse,
            );
            expect(
              hasRemovalSignal(await charlie.loadGroupMessages(groupId)),
              isFalse,
            );
          } finally {
            alice.dispose();
            bob.dispose();
            charlie.dispose();
          }
        },
      );

      test(
        'NW-008 duplicate libp2p-style deliveries keep one visible message per receiver',
        () async {
          final alice = GroupTestUser.create(
            peerId: 'alice-nw008-duplicate-peer',
            username: 'Alice',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'bob-nw008-duplicate-peer',
            username: 'Bob',
            network: network,
          );
          final charlie = GroupTestUser.create(
            peerId: 'charlie-nw008-duplicate-peer',
            username: 'Charlie',
            network: network,
          );
          const groupId = 'group-nw008-duplicate-connections';
          const messageId = 'nw008-duplicate-live-message';
          const text = 'NW-008 duplicate connection delivery';

          try {
            await alice.createGroup(groupId: groupId, name: 'NW-008');
            await alice.addMember(groupId: groupId, invitee: bob);
            await alice.addMember(groupId: groupId, invitee: charlie);
            await _saveKey(alice, groupId, 1, 'nw008-epoch-1');
            await _saveKey(bob, groupId, 1, 'nw008-epoch-1');
            await _saveKey(charlie, groupId, 1, 'nw008-epoch-1');

            alice.start();
            bob.start();
            charlie.start();

            network.duplicateOnDeliver = true;
            final (result, sent) = await alice.sendGroupMessageViaBridge(
              groupId: groupId,
              text: text,
              messageId: messageId,
              timestamp: DateTime.now().toUtc(),
            );

            expect(result, SendGroupMessageResult.success);
            expect(sent, isNotNull);
            expect(sent!.status, 'sent');
            expect(sent.isIncoming, isFalse);

            await pumpUntilAsync(() async {
              final bobRows = await bob.loadGroupMessages(groupId);
              final charlieRows = await charlie.loadGroupMessages(groupId);
              return bobRows.any((message) => message.id == messageId) &&
                  charlieRows.any((message) => message.id == messageId);
            }, maxPumps: 80);
            await pump();

            expect(
              network.totalDeliveries,
              4,
              reason:
                  'Two physical duplicate deliveries should be emitted to each active receiver',
            );
            expect(
              network.deliveryRecords
                  .where((record) => record['messageId'] == messageId)
                  .map((record) => record['receiverPeerId'])
                  .toSet(),
              {bob.peerId, charlie.peerId},
            );

            for (final receiver in <GroupTestUser>[bob, charlie]) {
              final rows = await receiver.loadGroupMessages(groupId);
              final matchingRows = rows
                  .where(
                    (message) => message.id == messageId && message.isIncoming,
                  )
                  .toList();
              expect(
                matchingRows,
                hasLength(1),
                reason:
                    '${receiver.username} should keep one visible row despite duplicate delivery paths',
              );
              expect(matchingRows.single.text, text);
              expect(matchingRows.single.status, 'delivered');
              expect(await receiver.msgRepo.getUnreadCount(groupId), 1);
            }

            final aliceRows = await alice.loadGroupMessages(groupId);
            expect(
              aliceRows.where(
                (message) => message.id == messageId && !message.isIncoming,
              ),
              hasLength(1),
            );
            final storedPayload = latestBridgePayload(
              alice.bridge,
              'group:inboxStore',
            );
            expect(
              (storedPayload['recipientPeerIds'] as List<dynamic>)
                  .cast<String>()
                  .toSet(),
              {bob.peerId, charlie.peerId},
            );
          } finally {
            network.duplicateOnDeliver = false;
            alice.dispose();
            bob.dispose();
            charlie.dispose();
          }
        },
      );

      test(
        'MS004 partition replay preserves quoted parent ids and deterministic order',
        () async {
          final admin = GroupTestUser.create(
            peerId: 'admin-ms004-partition-peer',
            username: 'Alice',
            network: network,
          );
          final onlineReader = GroupTestUser.create(
            peerId: 'reader-ms004-online-peer',
            username: 'Bob',
            network: network,
          );
          final partitionedReader = GroupTestUser.create(
            peerId: 'reader-ms004-offline-peer',
            username: 'Carol',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final partitionBridge =
              partitionedReader.bridge as _CursorInboxBridge;

          const groupId = 'group-ms004-partition-replay';
          await admin.createGroup(groupId: groupId, name: 'MS-004 Replay');
          await admin.addMember(groupId: groupId, invitee: onlineReader);
          await admin.addMember(groupId: groupId, invitee: partitionedReader);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(onlineReader, groupId, 1, 'k1');
          await _saveKey(partitionedReader, groupId, 1, 'k1');

          final members = await admin.groupRepo.getMembers(groupId);
          for (final member in members) {
            await onlineReader.groupRepo.saveMember(member);
          }

          admin.start();
          onlineReader.start();
          partitionedReader.start();

          network.unsubscribe(groupId, partitionedReader.peerId);
          expect(
            network.isSubscribed(groupId, partitionedReader.peerId),
            isFalse,
          );

          final sentAt = DateTime.now().toUtc().subtract(
            const Duration(days: 1),
          );
          final (parentResult, parent) = await admin.sendGroupMessageViaBridge(
            groupId: groupId,
            text: 'Partition parent',
            messageId: 'ms004-partition-parent',
            timestamp: sentAt,
          );
          expect(parentResult, SendGroupMessageResult.success);
          expect(parent, isNotNull);
          await pumpUntilAsync(() async {
            final messages = await onlineReader.loadGroupMessages(groupId);
            return messages.any(
              (message) => message.id == 'ms004-partition-parent',
            );
          }, maxPumps: 120);

          final (replyResult, reply) = await onlineReader
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: 'Partition reply',
                quotedMessageId: parent!.id,
                messageId: 'ms004-partition-a-reply',
                timestamp: sentAt,
              );
          expect(replyResult, SendGroupMessageResult.success);
          expect(reply, isNotNull);
          await pumpUntilAsync(() async {
            final messages = await admin.loadGroupMessages(groupId);
            return messages.any(
              (message) => message.id == 'ms004-partition-a-reply',
            );
          }, maxPumps: 120);

          final parentInbox = bridgePayloads(
            admin.bridge,
            'group:inboxStore',
          ).single;
          final replyInbox = bridgePayloads(
            onlineReader.bridge,
            'group:inboxStore',
          ).single;
          expect(
            (parentInbox['recipientPeerIds'] as List<dynamic>).cast<String>(),
            contains(partitionedReader.peerId),
          );
          expect(
            (replyInbox['recipientPeerIds'] as List<dynamic>).cast<String>(),
            contains(partitionedReader.peerId),
          );

          _addRelayStoredMessagePage(
            receiverBridge: partitionBridge,
            groupId: groupId,
            fromPeerId: admin.peerId,
            storedMessage: parentInbox['message'] as String,
            nextCursor: 'cursor-ms004-reply',
          );
          _addRelayStoredMessagePage(
            receiverBridge: partitionBridge,
            groupId: groupId,
            fromPeerId: onlineReader.peerId,
            storedMessage: replyInbox['message'] as String,
            cursor: 'cursor-ms004-reply',
          );

          await rejoinGroupTopics(
            bridge: partitionedReader.bridge,
            groupRepo: partitionedReader.groupRepo,
          );
          await drainGroupOfflineInbox(
            bridge: partitionedReader.bridge,
            groupRepo: partitionedReader.groupRepo,
            msgRepo: partitionedReader.msgRepo,
          );
          network.subscribe(groupId, partitionedReader.peerId);

          Future<void> expectTimeline(GroupTestUser user) async {
            final messages = (await user.loadGroupMessages(groupId))
                .where(
                  (message) =>
                      message.id == 'ms004-partition-parent' ||
                      message.id == 'ms004-partition-a-reply',
                )
                .toList(growable: false);
            expect(
              messages.map((message) => message.id).toList(),
              ['ms004-partition-parent', 'ms004-partition-a-reply'],
              reason:
                  '${user.username} should keep the replayed parent/reply order',
            );
            expect(
              messages
                  .singleWhere(
                    (message) => message.id == 'ms004-partition-a-reply',
                  )
                  .quotedMessageId,
              'ms004-partition-parent',
            );
          }

          await expectTimeline(admin);
          await expectTimeline(onlineReader);
          await expectTimeline(partitionedReader);

          admin.dispose();
          onlineReader.dispose();
          partitionedReader.dispose();
        },
      );

      test('full lifecycle round-trip', () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-round-trip-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'reader-round-trip-peer',
          username: 'Bob',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final charlie = GroupTestUser.create(
          peerId: 'reader-round-trip-online-peer',
          username: 'Charlie',
          network: network,
        );
        final bobBridge = bob.bridge as _CursorInboxBridge;

        const groupId = 'group-round-trip';
        await admin.createGroup(groupId: groupId, name: 'Round Trip');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);
        await _saveKey(admin, groupId, 1, 'k1');
        await _saveKey(bob, groupId, 1, 'k1');
        await _saveKey(charlie, groupId, 1, 'k1');

        admin.start();
        bob.start();
        charlie.start();

        await admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'Before pause',
        );
        await pump();

        network.unsubscribe(groupId, bob.peerId);

        await simulateBackgroundForegroundCycle(
          bridge: bob.bridge,
          p2pService: FakeP2PService(),
          messageRepo: InMemoryMessageRepository(),
          groupMsgRepo: bob.msgRepo,
          afterPause: () async {
            await admin.sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'While paused',
            );
            _injectInboxMessageFromLatestStore(
              senderBridge: admin.bridge,
              receiverBridge: bobBridge,
              receiverPeerId: bob.peerId,
              groupId: groupId,
            );
          },
          afterResume: () async {
            await drainGroupOfflineInbox(
              bridge: bob.bridge,
              groupRepo: bob.groupRepo,
              msgRepo: bob.msgRepo,
            );
            network.subscribe(groupId, bob.peerId);
          },
        );

        await pump();
        final bobMessages = await bob.loadGroupMessages(groupId);
        final bobIncoming = bobMessages.where((message) => message.isIncoming);
        expect(bobIncoming, hasLength(2));
        expect(bobIncoming.map((message) => message.text).toSet(), {
          'Before pause',
          'While paused',
        });
        expect(
          bobMessages.where((message) => message.text == 'While paused'),
          hasLength(1),
        );

        admin.dispose();
        bob.dispose();
        charlie.dispose();
      });

      test('failed message retry after network recovery', () async {
        final admin = GroupTestUser.create(
          peerId: 'admin-retry-peer',
          username: 'Alice',
          network: network,
          bridge: _Section10MirroringBridge(
            network: network,
            msgRepo: InMemoryGroupMessageRepository(),
            groupRepo: InMemoryGroupRepository(),
            publishFailuresRemaining: 1,
          ),
        );
        final bob = GroupTestUser.create(
          peerId: 'reader-retry-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'reader-retry-peer-2',
          username: 'Charlie',
          network: network,
        );

        const groupId = 'group-retry-after-network';
        await admin.createGroup(groupId: groupId, name: 'Retry After Recovery');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);
        await _saveKey(admin, groupId, 1, 'k1');
        await _saveKey(bob, groupId, 1, 'k1');
        await _saveKey(charlie, groupId, 1, 'k1');

        admin.start();
        bob.start();
        charlie.start();

        final (initialResult, initialSent) = await admin
            .sendGroupMessageViaBridge(groupId: groupId, text: 'Retry me');

        expect(initialResult, SendGroupMessageResult.error);
        expect(initialSent, isNotNull);
        expect(initialSent!.status, 'failed');

        final retried = await retryFailedGroupMessages(
          groupMsgRepo: admin.msgRepo,
          groupRepo: admin.groupRepo,
          identityRepo: _Section10IdentityRepository(_identityForUser(admin)),
          bridge: admin.bridge,
          mediaAttachmentRepo: admin.mediaAttachmentRepo,
        );

        expect(retried, 1);

        final finalMessage = await _latestOutgoingMessage(
          admin.msgRepo,
          groupId,
          text: 'Retry me',
        );
        expect(finalMessage.id, initialSent.id);
        expect(finalMessage.status, 'sent');

        await pump();
        final bobMessages = await bob.loadGroupMessages(groupId);
        expect(
          bobMessages.where((message) => message.id == initialSent.id),
          hasLength(1),
        );

        final charlieMessages = await charlie.loadGroupMessages(groupId);
        expect(
          charlieMessages.where((message) => message.id == initialSent.id),
          hasLength(1),
        );

        admin.dispose();
        bob.dispose();
        charlie.dispose();
      });

      test(
        'OB-011 fake-network release telemetry identifies missed-message causes',
        () async {
          final flowEvents = <Map<String, dynamic>>[];
          debugSetFlowEventSink(flowEvents.add);
          addTearDown(() => debugSetFlowEventSink(null));

          final adminBridge = _Section10MirroringBridge(
            network: network,
            msgRepo: InMemoryGroupMessageRepository(),
            groupRepo: InMemoryGroupRepository(),
          );
          final admin = GroupTestUser.create(
            peerId: 'admin-ob011-telemetry',
            username: 'Alice',
            network: network,
            bridge: adminBridge,
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-ob011-telemetry',
            username: 'Bob',
            network: network,
            bridge: _CursorInboxBridge(),
          );

          const groupId = 'group-ob011-release-telemetry';
          await admin.createGroup(groupId: groupId, name: 'OB-011 Telemetry');
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');

          admin.start();
          bob.start();
          bob.unsubscribeFromGroup(groupId);

          final (result, missedLiveMessage) = await admin
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: 'OB-011 live miss recovered by replay',
              );
          expect(result, SendGroupMessageResult.successNoPeers);
          expect(missedLiveMessage, isNotNull);

          final report = emitGroupMissedMessageTelemetryReport(
            expectedDeliveries: <GroupDeliveryExpectation>[
              GroupDeliveryExpectation(
                groupId: groupId,
                messageId: missedLiveMessage!.id,
                senderPeerId: admin.peerId,
                recipientPeerId: bob.peerId,
                keyEpoch: missedLiveMessage.keyGeneration,
                expectedVia: 'live_or_replay',
              ),
              ..._ob011SyntheticExpectations(groupId: groupId, admin: admin),
            ],
            observedDeliveries: const <GroupDeliveryObservation>[],
            diagnostics: <Map<String, dynamic>>[
              _ob011Diagnostic(
                groupId: groupId,
                messageId: missedLiveMessage.id,
                recipientPeerId: bob.peerId,
                event: 'GROUP_SEND_MSG_USE_CASE_SUCCESS_NO_PEERS',
                cause: ob011CauseTransport,
                reason: 'zero_peers',
                resolution: 'relay_inbox_pending',
              ),
              ..._ob011SyntheticDiagnostics(groupId: groupId),
            ],
          );

          final summary = report['summary'] as Map;
          expect(summary['unknownCount'], 0);
          expect(
            summary['coveredCauseClasses'],
            equals(ob011RequiredCauseClasses.toList()..sort()),
          );
          expect(
            flowEvents.any(
              (event) => event['event'] == ob011MissedMessageTelemetryEvent,
            ),
            isTrue,
          );

          bob.subscribeToGroup(groupId);
          _injectInboxMessageFromLatestStore(
            senderBridge: admin.bridge,
            receiverBridge: bob.bridge as _CursorInboxBridge,
            receiverPeerId: bob.peerId,
            groupId: groupId,
          );
          await drainGroupOfflineInbox(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            msgRepo: bob.msgRepo,
          );
          final bobMessages = await bob.loadGroupMessages(groupId);
          expect(
            bobMessages.where(
              (message) =>
                  message.id == missedLiveMessage.id &&
                  message.text == 'OB-011 live miss recovered by replay',
            ),
            hasLength(1),
          );

          admin.dispose();
          bob.dispose();
        },
      );

      test(
        'IR-007 DE-008 publish failure branch retries over fake network with same id and one row',
        () async {
          final adminBridge = _Section10MirroringBridge(
            network: network,
            msgRepo: InMemoryGroupMessageRepository(),
            groupRepo: InMemoryGroupRepository(),
            publishTimeoutsRemaining: 1,
            inboxStoreFailuresRemaining: 1,
          );
          final admin = GroupTestUser.create(
            peerId: 'admin-de008-timeout-peer',
            username: 'Alice',
            network: network,
            bridge: adminBridge,
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-de008-timeout-peer',
            username: 'Bob',
            network: network,
          );

          const groupId = 'group-de008-timeout-retry';
          const text = 'Timeout then retry over fake network';
          await admin.createGroup(groupId: groupId, name: 'Timeout Retry');
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');

          admin.start();
          bob.start();

          final (initialResult, initialMessage) = await admin
              .sendGroupMessageViaBridge(groupId: groupId, text: text);

          expect(initialResult, SendGroupMessageResult.error);
          expect(initialMessage, isNotNull);
          expect(initialMessage!.status, 'failed');
          expect(initialMessage.wireEnvelope, isNotNull);
          expect(initialMessage.inboxRetryPayload, isNotNull);
          expect(initialMessage.inboxStored, isFalse);
          final inboxOnlyRows = await admin.msgRepo
              .getMessagesWithFailedInboxStore();
          expect(
            inboxOnlyRows.map((row) => row.id),
            isNot(contains(initialMessage.id)),
          );
          final failedRows = await admin.msgRepo.getFailedOutgoingMessages();
          expect(failedRows.map((row) => row.id), [initialMessage.id]);

          final senderRows = await admin.loadGroupMessages(groupId);
          final initialOutgoing = senderRows
              .where((message) => !message.isIncoming && message.text == text)
              .toList(growable: false);
          expect(initialOutgoing, hasLength(1));
          expect(initialOutgoing.single.id, initialMessage.id);
          expect(initialOutgoing.single.status, 'failed');
          expect(await bob.loadGroupMessages(groupId), isEmpty);

          final retried = await retryFailedGroupMessages(
            groupMsgRepo: admin.msgRepo,
            groupRepo: admin.groupRepo,
            identityRepo: _Section10IdentityRepository(_identityForUser(admin)),
            bridge: admin.bridge,
            mediaAttachmentRepo: admin.mediaAttachmentRepo,
          );
          expect(retried, 1);

          await pumpUntilAsync(() async {
            final bobMessages = await bob.loadGroupMessages(groupId);
            return bobMessages
                    .where(
                      (message) =>
                          message.isIncoming &&
                          message.id == initialMessage.id &&
                          message.text == text,
                    )
                    .length ==
                1;
          });

          final recovered = await admin.msgRepo.getMessage(initialMessage.id);
          expect(recovered, isNotNull);
          expect(recovered!.id, initialMessage.id);
          expect(recovered.status, 'sent');
          expect(recovered.wireEnvelope, isNull);
          expect(recovered.inboxRetryPayload, isNull);
          expect(await admin.msgRepo.getFailedOutgoingMessages(), isEmpty);

          final senderRowsAfterRetry = await admin.loadGroupMessages(groupId);
          final finalOutgoing = senderRowsAfterRetry
              .where((message) => !message.isIncoming && message.text == text)
              .toList(growable: false);
          expect(finalOutgoing, hasLength(1));
          expect(finalOutgoing.single.id, initialMessage.id);
          expect(finalOutgoing.single.status, 'sent');
          expect(
            senderRowsAfterRetry.where(
              (message) =>
                  !message.isIncoming &&
                  (message.status == 'pending' || message.status == 'failed'),
            ),
            isEmpty,
          );

          final bobMessages = await bob.loadGroupMessages(groupId);
          expect(
            bobMessages.where(
              (message) =>
                  message.isIncoming &&
                  message.id == initialMessage.id &&
                  message.text == text,
            ),
            hasLength(1),
          );
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:publish'),
            hasLength(2),
          );
          expect(
            adminBridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
            hasLength(2),
          );

          admin.dispose();
          bob.dispose();
        },
      );

      test(
        'DE-012 dispatcher overflow diagnostic drains inbox replay for a dropped group message',
        () async {
          final admin = GroupTestUser.create(
            peerId: 'admin-de012-overflow',
            username: 'Alice',
            network: network,
          );
          final bobDiagnostics =
              StreamController<Map<String, dynamic>>.broadcast();
          late final GroupTestUser bob;
          var recoveryCount = 0;
          bob = GroupTestUser.create(
            peerId: 'reader-de012-overflow',
            username: 'Bob',
            network: network,
            bridge: _CursorInboxBridge(),
            groupDiagnosticEvents: bobDiagnostics.stream,
            recoverFromDispatcherOverflow: (diagnostic) async {
              recoveryCount++;
              await drainGroupOfflineInbox(
                bridge: bob.bridge,
                groupRepo: bob.groupRepo,
                msgRepo: bob.msgRepo,
                groupMessageListener: bob.groupMessageListener,
                selfPeerId: bob.peerId,
              );
            },
          );
          addTearDown(() {
            admin.dispose();
            bob.dispose();
            bobDiagnostics.close();
          });

          final bobBridge = bob.bridge as _CursorInboxBridge;
          const groupId = 'group-de012-overflow';
          const messageId = 'de012-overflow-replay';
          const text = 'DE-012 overflow replay recovery';
          await admin.createGroup(
            groupId: groupId,
            name: 'DE-012 Overflow Recovery',
          );
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');
          network.unsubscribe(groupId, bob.peerId);

          admin.start();
          bob.start();

          final (result, sent) = await admin.sendGroupMessageViaBridge(
            groupId: groupId,
            text: text,
            messageId: messageId,
            publishTopicPeersOverride: 1,
          );

          expect(result, SendGroupMessageResult.success);
          expect(sent, isNotNull);
          expect(sent!.inboxStored, isTrue);
          expect(admin.bridge.commandLog, contains('group:publish'));
          expect(admin.bridge.commandLog, contains('group:inboxStore'));

          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(await bob.loadGroupMessages(groupId), isEmpty);

          _injectInboxMessageFromLatestStore(
            senderBridge: admin.bridge,
            receiverBridge: bobBridge,
            receiverPeerId: bob.peerId,
            groupId: groupId,
          );

          bobDiagnostics.add({
            'event': 'group:dispatcher_overflow',
            'state': 'overflow',
            'lastEvent': 'group_message:received',
            'droppedCount': 1,
            'queueDepth': 2,
            'maxQueueSize': 2,
          });

          final deadline = DateTime.now().add(const Duration(seconds: 2));
          List<GroupMessage> bobMessages = const <GroupMessage>[];
          while (DateTime.now().isBefore(deadline)) {
            bobMessages = await bob.loadGroupMessages(groupId);
            if (bobMessages.any(
              (message) =>
                  message.isIncoming &&
                  message.id == messageId &&
                  message.text == text,
            )) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }

          final recovered = bobMessages.where(
            (message) =>
                message.isIncoming &&
                message.id == messageId &&
                message.text == text,
          );
          expect(recovered, hasLength(1));
          expect(recoveryCount, 1);
          expect(bob.bridge.commandLog, contains('group:inboxRetrieveCursor'));
        },
      );

      test(
        'OB-006 dispatcher overflow diagnostics expose replay recovery result',
        () async {
          final flowEvents = <Map<String, dynamic>>[];
          debugSetFlowEventSink(flowEvents.add);
          addTearDown(() => debugSetFlowEventSink(null));

          final admin = GroupTestUser.create(
            peerId: 'admin-ob006-overflow',
            username: 'Alice',
            network: network,
          );
          final bobDiagnostics =
              StreamController<Map<String, dynamic>>.broadcast();
          late final GroupTestUser bob;
          var recoveryCount = 0;
          final recoveryDone = Completer<void>();
          final recoveryDiagnostics = <Map<String, dynamic>>[];
          bob = GroupTestUser.create(
            peerId: 'reader-ob006-overflow',
            username: 'Bob',
            network: network,
            bridge: _CursorInboxBridge(),
            groupDiagnosticEvents: bobDiagnostics.stream,
            recoverFromDispatcherOverflow: (diagnostic) async {
              recoveryCount++;
              recoveryDiagnostics.add(Map<String, dynamic>.from(diagnostic));
              await drainGroupOfflineInbox(
                bridge: bob.bridge,
                groupRepo: bob.groupRepo,
                msgRepo: bob.msgRepo,
                groupMessageListener: bob.groupMessageListener,
                selfPeerId: bob.peerId,
              );
              if (!recoveryDone.isCompleted) {
                recoveryDone.complete();
              }
            },
          );
          addTearDown(() {
            admin.dispose();
            bob.dispose();
            bobDiagnostics.close();
          });

          final bobBridge = bob.bridge as _CursorInboxBridge;
          const groupId = 'group-ob006-overflow';
          const messageId = 'ob006-overflow-replay';
          const text = 'OB-006 overflow replay recovery';
          await admin.createGroup(
            groupId: groupId,
            name: 'OB-006 Overflow Recovery',
          );
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');
          network.unsubscribe(groupId, bob.peerId);

          admin.start();
          bob.start();

          final (result, sent) = await admin.sendGroupMessageViaBridge(
            groupId: groupId,
            text: text,
            messageId: messageId,
            publishTopicPeersOverride: 1,
          );

          expect(result, SendGroupMessageResult.success);
          expect(sent, isNotNull);
          expect(sent!.inboxStored, isTrue);
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(await bob.loadGroupMessages(groupId), isEmpty);

          _injectInboxMessageFromLatestStore(
            senderBridge: admin.bridge,
            receiverBridge: bobBridge,
            receiverPeerId: bob.peerId,
            groupId: groupId,
          );

          bobDiagnostics.add({
            'event': 'group:dispatcher_overflow',
            'state': 'overflow',
            'lastEvent': 'group_message:received',
            'droppedCount': 4,
            'queueDepth': 5,
            'maxQueueSize': 5,
          });

          await recoveryDone.future.timeout(const Duration(seconds: 2));
          final deadline = DateTime.now().add(const Duration(seconds: 2));
          List<GroupMessage> bobMessages = const <GroupMessage>[];
          while (DateTime.now().isBefore(deadline)) {
            bobMessages = await bob.loadGroupMessages(groupId);
            if (bobMessages.any(
              (message) =>
                  message.isIncoming &&
                  message.id == messageId &&
                  message.text == text,
            )) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }

          expect(
            bobMessages.where(
              (message) =>
                  message.isIncoming &&
                  message.id == messageId &&
                  message.text == text,
            ),
            hasLength(1),
          );
          expect(recoveryCount, 1);
          expect(
            recoveryDiagnostics.single['lastEvent'],
            'group_message:received',
          );
          expect(recoveryDiagnostics.single['droppedCount'], 4);
          expect(recoveryDiagnostics.single['queueDepth'], 5);
          expect(recoveryDiagnostics.single['maxQueueSize'], 5);

          final requested = flowEvents.singleWhere(
            (event) =>
                event['event'] ==
                'GROUP_DISPATCHER_OVERFLOW_RECOVERY_REQUESTED',
          );
          final done = flowEvents.singleWhere(
            (event) =>
                event['event'] == 'GROUP_DISPATCHER_OVERFLOW_RECOVERY_DONE',
          );
          for (final event in [requested, done]) {
            final details = event['details'] as Map<String, dynamic>;
            expect(details['state'], 'overflow');
            expect(details['lastEvent'], 'group_message:received');
            expect(details['droppedCount'], 4);
            expect(details['queueDepth'], 5);
            expect(details['maxQueueSize'], 5);
          }
          expect(bob.bridge.commandLog, contains('group:inboxRetrieveCursor'));
        },
      );

      test(
        'IR-017 fake-network dispatcher overflow replay restores and dedupes dropped live event',
        () async {
          final flowEvents = <Map<String, dynamic>>[];
          debugSetFlowEventSink(flowEvents.add);
          addTearDown(() => debugSetFlowEventSink(null));

          final admin = GroupTestUser.create(
            peerId: 'admin-ir017-overflow',
            username: 'Alice',
            network: network,
          );
          final bobDiagnostics =
              StreamController<Map<String, dynamic>>.broadcast();
          late final GroupTestUser bob;
          var recoveryCount = 0;
          final firstRecovery = Completer<void>();
          final secondRecovery = Completer<void>();
          final recoveryDiagnostics = <Map<String, dynamic>>[];
          bob = GroupTestUser.create(
            peerId: 'reader-ir017-overflow',
            username: 'Bob',
            network: network,
            bridge: _CursorInboxBridge(),
            groupDiagnosticEvents: bobDiagnostics.stream,
            recoverFromDispatcherOverflow: (diagnostic) async {
              recoveryCount++;
              recoveryDiagnostics.add(Map<String, dynamic>.from(diagnostic));
              await drainGroupOfflineInbox(
                bridge: bob.bridge,
                groupRepo: bob.groupRepo,
                msgRepo: bob.msgRepo,
                groupMessageListener: bob.groupMessageListener,
                selfPeerId: bob.peerId,
              );
              if (recoveryCount == 1 && !firstRecovery.isCompleted) {
                firstRecovery.complete();
              } else if (recoveryCount == 2 && !secondRecovery.isCompleted) {
                secondRecovery.complete();
              }
            },
          );
          addTearDown(() {
            admin.dispose();
            bob.dispose();
            bobDiagnostics.close();
          });

          final bobBridge = bob.bridge as _CursorInboxBridge;
          const groupId = 'group-ir017-overflow';
          const messageId = 'ir017-overflow-replay';
          const text = 'IR-017 overflow replay recovery';
          await admin.createGroup(
            groupId: groupId,
            name: 'IR-017 Overflow Recovery',
          );
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');
          network.unsubscribe(groupId, bob.peerId);

          admin.start();
          bob.start();

          final (result, sent) = await admin.sendGroupMessageViaBridge(
            groupId: groupId,
            text: text,
            messageId: messageId,
            publishTopicPeersOverride: 1,
          );

          expect(result, SendGroupMessageResult.success);
          expect(sent, isNotNull);
          expect(sent!.inboxStored, isTrue);
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(await bob.loadGroupMessages(groupId), isEmpty);

          _injectInboxMessageFromLatestStore(
            senderBridge: admin.bridge,
            receiverBridge: bobBridge,
            receiverPeerId: bob.peerId,
            groupId: groupId,
          );

          bobDiagnostics.add({
            'event': 'group:dispatcher_overflow',
            'state': 'overflow',
            'lastEvent': 'group_message:received',
            'droppedCount': 1,
            'queueDepth': 2,
            'maxQueueSize': 2,
          });
          await firstRecovery.future.timeout(const Duration(seconds: 2));
          await Future<void>.delayed(const Duration(milliseconds: 50));

          var bobMessages = await bob.loadGroupMessages(groupId);
          expect(
            bobMessages.where(
              (message) =>
                  message.isIncoming &&
                  message.id == messageId &&
                  message.text == text,
            ),
            hasLength(1),
          );

          bobDiagnostics.add({
            'event': 'group:dispatcher_overflow',
            'state': 'overflow',
            'lastEvent': 'group_message:received',
            'droppedCount': 1,
            'queueDepth': 2,
            'maxQueueSize': 2,
          });
          await secondRecovery.future.timeout(const Duration(seconds: 2));

          bobMessages = await bob.loadGroupMessages(groupId);
          expect(
            bobMessages.where(
              (message) =>
                  message.isIncoming &&
                  message.id == messageId &&
                  message.text == text,
            ),
            hasLength(1),
          );
          expect(recoveryCount, 2);
          expect(
            recoveryDiagnostics.map((diagnostic) => diagnostic['lastEvent']),
            everyElement('group_message:received'),
          );
          expect(bob.bridge.commandLog, contains('group:inboxRetrieveCursor'));

          final requested = flowEvents.where(
            (event) =>
                event['event'] ==
                'GROUP_DISPATCHER_OVERFLOW_RECOVERY_REQUESTED',
          );
          expect(requested, hasLength(2));
          for (final event in requested) {
            final details = event['details'] as Map<String, dynamic>;
            expect(details['state'], 'overflow');
            expect(details['lastEvent'], 'group_message:received');
            expect(details['droppedCount'], 1);
          }
        },
      );

      test(
        'DE-013 malformed pubsub message is rejected and later valid delivery persists',
        () async {
          final flowEvents = <Map<String, dynamic>>[];
          debugSetFlowEventSink(flowEvents.add);
          addTearDown(() => debugSetFlowEventSink(null));

          final admin = GroupTestUser.create(
            peerId: 'admin-de013-schema',
            username: 'Alice',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-de013-schema',
            username: 'Bob',
            network: network,
          );
          addTearDown(() {
            admin.dispose();
            bob.dispose();
          });

          const groupId = 'group-de013-schema';
          await admin.createGroup(
            groupId: groupId,
            name: 'DE-013 Schema Validation',
          );
          await admin.addMember(groupId: groupId, invitee: bob);
          admin.start();
          bob.start();

          final now = DateTime.now().toUtc().toIso8601String();
          await network.publish(groupId, admin.peerId, {
            'groupId': groupId,
            'senderId': admin.peerId,
            'senderUsername': admin.username,
            'text': 'malformed missing key epoch',
            'timestamp': now,
            'messageId': 'de013-malformed-network',
          }, senderDeviceId: admin.deviceId);
          await Future<void>.delayed(const Duration(milliseconds: 50));

          expect(await bob.loadGroupMessages(groupId), isEmpty);
          expect(
            await bob.msgRepo.getMessage('de013-malformed-network'),
            isNull,
          );

          await network.publish(groupId, admin.peerId, {
            'groupId': groupId,
            'senderId': admin.peerId,
            'senderUsername': admin.username,
            'keyEpoch': 0,
            'text': 'valid after malformed pubsub event',
            'timestamp': now,
            'messageId': 'de013-valid-network',
          }, senderDeviceId: admin.deviceId);

          final deadline = DateTime.now().add(const Duration(seconds: 2));
          List<GroupMessage> bobMessages = const <GroupMessage>[];
          while (DateTime.now().isBefore(deadline)) {
            bobMessages = await bob.loadGroupMessages(groupId);
            if (bobMessages.any(
              (message) =>
                  message.id == 'de013-valid-network' &&
                  message.text == 'valid after malformed pubsub event',
            )) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }

          expect(
            bobMessages.where(
              (message) =>
                  message.id == 'de013-valid-network' &&
                  message.text == 'valid after malformed pubsub event',
            ),
            hasLength(1),
          );
          expect(
            flowEvents.where(
              (event) =>
                  event['event'] == 'GROUP_MESSAGE_LISTENER_SCHEMA_REJECTED',
            ),
            hasLength(1),
          );
        },
      );

      test(
        'DE-014 decrypt failure repairs from durable replay and preserves later fake-network delivery',
        () async {
          final bobDiagnostics =
              StreamController<Map<String, dynamic>>.broadcast();
          final pendingRepo = _InMemoryGroupPendingKeyRepairRepository();
          final repairRequests = <GroupKeyRepairRequest>[];
          final admin = GroupTestUser.create(
            peerId: 'admin-de014-repair',
            username: 'Alice',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-de014-repair',
            username: 'Bob',
            network: network,
            bridge: _CursorInboxBridge(),
            groupDiagnosticEvents: bobDiagnostics.stream,
            pendingKeyRepairRepo: pendingRepo,
            requestGroupKeyRepair: repairRequests.add,
          );
          addTearDown(() {
            admin.dispose();
            bob.dispose();
            bobDiagnostics.close();
          });

          final bobBridge = bob.bridge as _CursorInboxBridge;
          const groupId = 'group-de014-repair';
          const messageId = 'de014-repaired-message';
          const messageText = 'DE-014 repaired from durable replay';
          await admin.createGroup(
            groupId: groupId,
            name: 'DE-014 Decrypt Repair',
          );
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(admin, groupId, 2, 'k2');
          await _saveKey(bob, groupId, 1, 'k1');

          admin.start();
          bob.start();

          final livePlaceholderFuture = bob
              .groupMessageListener
              .groupMessageStream
              .first
              .timeout(const Duration(seconds: 1));
          bobDiagnostics.add({
            'event': 'group:decryption_failed',
            'groupId': groupId,
            'senderId': admin.peerId,
            'keyEpoch': 2,
            'localKeyEpoch': 1,
            'error': 'cipher: message authentication failed',
          });

          final livePlaceholder = await livePlaceholderFuture;
          final liveRepairId = liveGroupPendingKeyRepairId(
            groupId: groupId,
            senderPeerId: admin.peerId,
            keyEpoch: 2,
            localKeyEpoch: 1,
          );
          expect(livePlaceholder.id, liveRepairId);
          expect(livePlaceholder.text, groupPendingKeyRepairPlaceholderText);
          expect(livePlaceholder.status, groupPendingKeyRepairStatusPendingKey);
          expect(await bob.msgRepo.getMessage(messageId), isNull);
          expect(repairRequests, hasLength(1));
          expect(
            repairRequests.single.reason,
            groupKeyRepairReasonLiveDiagnostic,
          );

          final replayEnvelope = await _signedReplayRelayMessage(
            bridge: admin.bridge,
            groupRepo: admin.groupRepo,
            groupId: groupId,
            payload: {
              'groupId': groupId,
              'senderId': admin.peerId,
              'senderUsername': admin.username,
              'keyEpoch': 2,
              'text': messageText,
              'timestamp': DateTime.now().toUtc().toIso8601String(),
              'messageId': messageId,
            },
            senderPeerId: admin.peerId,
            senderPublicKey: admin.publicKey,
            senderPrivateKey: admin.privateKey,
          );
          bobBridge.addPage(groupId, '', [replayEnvelope], '');

          await drainGroupOfflineInbox(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            msgRepo: bob.msgRepo,
            groupMessageListener: bob.groupMessageListener,
            pendingKeyRepairRepo: pendingRepo,
            requestGroupKeyRepair: repairRequests.add,
          );

          final durablePlaceholder = await bob.msgRepo.getMessage(messageId);
          expect(durablePlaceholder, isNotNull);
          expect(
            durablePlaceholder!.text,
            groupPendingKeyRepairPlaceholderText,
          );
          expect(
            durablePlaceholder.status,
            groupPendingKeyRepairStatusPendingKey,
          );
          expect(await bob.msgRepo.getMessage(liveRepairId), isNull);
          expect(repairRequests, hasLength(2));
          expect(
            repairRequests.last.reason,
            groupKeyRepairReasonOfflineMissingKey,
          );

          await _saveKey(bob, groupId, 2, 'k2');
          final repairRunner = GroupPendingKeyRepairRunner(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            msgRepo: bob.msgRepo,
            pendingKeyRepairRepo: pendingRepo,
            replayGroupEnvelope: bob.groupMessageListener.handleReplayEnvelope,
          );
          final repairedCount = await repairRunner.retryPendingRepairsForKey(
            groupId: groupId,
            keyEpoch: 2,
          );

          expect(repairedCount, 1);
          final repaired = await bob.msgRepo.getMessage(messageId);
          expect(repaired, isNotNull);
          expect(repaired!.text, messageText);
          expect(repaired.status, 'delivered');
          expect(repaired.keyGeneration, 2);
          final visibleAfterRepair = await bob.loadGroupMessages(groupId);
          expect(
            visibleAfterRepair.where((message) => message.id == messageId),
            hasLength(1),
          );

          const laterMessageId = 'de014-later-live';
          final (laterResult, laterSent) = await admin
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: 'DE-014 later fake-network delivery',
                messageId: laterMessageId,
              );
          expect(laterResult, SendGroupMessageResult.success);
          expect(laterSent, isNotNull);

          final deadline = DateTime.now().add(const Duration(seconds: 2));
          List<GroupMessage> bobMessages = const <GroupMessage>[];
          while (DateTime.now().isBefore(deadline)) {
            bobMessages = await bob.loadGroupMessages(groupId);
            if (bobMessages.any(
              (message) =>
                  message.id == laterMessageId &&
                  message.text == 'DE-014 later fake-network delivery',
            )) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }

          expect(
            bobMessages.where(
              (message) =>
                  message.id == laterMessageId &&
                  message.text == 'DE-014 later fake-network delivery',
            ),
            hasLength(1),
          );
        },
      );

      test(
        'OB-004 fake-network decryption diagnostic creates repair workflow without normal delivery',
        () async {
          final admin = GroupTestUser.create(
            peerId: 'admin-ob004-repair',
            username: 'Alice',
            network: network,
          );
          final pendingRepo = _InMemoryGroupPendingKeyRepairRepository();
          final repairRequests = <GroupKeyRepairRequest>[];
          final bob = GroupTestUser.create(
            peerId: 'reader-ob004-repair',
            username: 'Bob',
            network: network,
            pendingKeyRepairRepo: pendingRepo,
            requestGroupKeyRepair: repairRequests.add,
          );
          addTearDown(() {
            admin.dispose();
            bob.dispose();
          });

          const groupId = 'group-ob004-repair';
          await admin.createGroup(
            groupId: groupId,
            name: 'OB-004 Repair Workflow',
          );
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');

          admin.start();
          bob.start();

          final placeholderFuture = bob.groupMessageListener.groupMessageStream
              .where(
                (message) =>
                    message.status == groupPendingKeyRepairStatusPendingKey,
              )
              .first
              .timeout(const Duration(seconds: 1));

          final emitted = network.emitDecryptionFailureDiagnostic(
            receiverPeerOrDeviceId: bob.peerId,
            groupId: groupId,
            senderPeerId: admin.peerId,
            senderDeviceId: admin.deviceId,
            keyEpoch: 2,
            localKeyEpoch: 1,
            messageId: 'ob004-undecipherable-live',
            error: 'fake network cannot decrypt live message',
          );

          expect(emitted, 1);
          final placeholder = await placeholderFuture;
          final repairId = liveGroupPendingKeyRepairId(
            groupId: groupId,
            senderPeerId: admin.peerId,
            keyEpoch: 2,
            localKeyEpoch: 1,
          );

          expect(placeholder.id, repairId);
          expect(placeholder.groupId, groupId);
          expect(placeholder.senderPeerId, admin.peerId);
          expect(placeholder.text, groupPendingKeyRepairPlaceholderText);
          expect(placeholder.status, groupPendingKeyRepairStatusPendingKey);
          expect(placeholder.keyGeneration, 2);

          final bobMessages = await bob.loadGroupMessages(groupId);
          expect(bobMessages, hasLength(1));
          expect(bobMessages.single.id, repairId);
          expect(
            bobMessages.any(
              (message) =>
                  message.text == 'fake network cannot decrypt live message',
            ),
            isFalse,
          );
          expect(pendingRepo.repairs, hasLength(1));
          expect(pendingRepo.repairs.values.single.id, repairId);
          expect(pendingRepo.repairs.values.single.replayEnvelopeJson, isNull);
          expect(repairRequests, hasLength(1));
          expect(repairRequests.single.groupId, groupId);
          expect(repairRequests.single.keyEpoch, 2);
          expect(
            repairRequests.single.reason,
            groupKeyRepairReasonLiveDiagnostic,
          );
          expect(repairRequests.single.messageId, repairId);
        },
      );

      test(
        'SV-005 tampered envelope diagnostic does not poison later fake-network delivery',
        () async {
          final bobDiagnostics =
              StreamController<Map<String, dynamic>>.broadcast();
          final pendingRepo = _InMemoryGroupPendingKeyRepairRepository();
          final repairRequests = <GroupKeyRepairRequest>[];
          final admin = GroupTestUser.create(
            peerId: 'admin-sv005-tamper',
            username: 'Alice',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-sv005-tamper',
            username: 'Bob',
            network: network,
            groupDiagnosticEvents: bobDiagnostics.stream,
            pendingKeyRepairRepo: pendingRepo,
            requestGroupKeyRepair: repairRequests.add,
          );
          addTearDown(() {
            admin.dispose();
            bob.dispose();
            bobDiagnostics.close();
          });

          const groupId = 'group-sv005-tamper';
          const laterMessageId = 'sv005-fake-network-valid-after-tamper';
          const laterText = 'SV-005 valid fake-network delivery after tamper';
          await admin.createGroup(
            groupId: groupId,
            name: 'SV-005 Tamper Recovery',
          );
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');

          admin.start();
          bob.start();

          final placeholderFuture = bob
              .groupMessageListener
              .groupMessageStream
              .first
              .timeout(const Duration(seconds: 1));
          bobDiagnostics.add({
            'event': 'group:decryption_failed',
            'groupId': groupId,
            'senderId': admin.peerId,
            'keyEpoch': 1,
            'localKeyEpoch': 1,
            'error': 'cipher: message authentication failed after tamper',
          });

          final placeholder = await placeholderFuture;
          expect(placeholder.text, groupPendingKeyRepairPlaceholderText);
          expect(placeholder.status, groupPendingKeyRepairStatusPendingKey);
          expect(await bob.msgRepo.getMessage(laterMessageId), isNull);
          expect(pendingRepo.repairs.values, hasLength(1));
          expect(repairRequests, hasLength(1));

          final (sendResult, sentMessage) = await admin
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: laterText,
                messageId: laterMessageId,
              );
          expect(sendResult, SendGroupMessageResult.success);
          expect(sentMessage, isNotNull);

          await pumpUntilAsync(() async {
            final messages = await bob.loadGroupMessages(groupId);
            return messages.any(
              (message) =>
                  message.id == laterMessageId && message.text == laterText,
            );
          });

          final bobMessages = await bob.loadGroupMessages(groupId);
          expect(
            bobMessages.where(
              (message) =>
                  message.id == laterMessageId && message.text == laterText,
            ),
            hasLength(1),
          );
          expect(
            bobMessages
                .where(
                  (message) =>
                      message.text ==
                      'SV-005 tampered nonce should not deliver',
                )
                .toList(),
            isEmpty,
          );
          expect(network.deliveryRecords, hasLength(1));
          expect(network.deliveryRecords.single['messageId'], laterMessageId);
        },
      );

      test(
        'DE-015 payload parse diagnostic does not poison later fake-network delivery',
        () async {
          final admin = GroupTestUser.create(
            peerId: 'admin-de015-parse',
            username: 'Alice',
            network: network,
          );
          final bobDiagnostics = network.registerDiagnosticPeer(
            'reader-de015-parse',
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-de015-parse',
            username: 'Bob',
            network: network,
            groupDiagnosticEvents: bobDiagnostics.stream,
          );
          addTearDown(() {
            admin.dispose();
            bob.dispose();
          });

          const groupId = 'group-de015-parse';
          const laterMessageId = 'de015-valid-network';
          const laterText = 'DE-015 valid fake-network delivery after parse';
          await admin.createGroup(
            groupId: groupId,
            name: 'DE-015 Payload Parse',
          );
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');

          admin.start();
          bob.start();

          final emitted = network.emitPayloadParseFailureDiagnostic(
            receiverPeerOrDeviceId: bob.deviceId,
            groupId: groupId,
            senderPeerId: admin.peerId,
            error: 'invalid character looking for beginning of value',
          );
          expect(emitted, 1);
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(await bob.loadGroupMessages(groupId), isEmpty);

          await admin.sendGroupMessage(
            groupId: groupId,
            text: laterText,
            messageId: laterMessageId,
          );

          final deadline = DateTime.now().add(const Duration(seconds: 2));
          List<GroupMessage> bobMessages = const <GroupMessage>[];
          while (DateTime.now().isBefore(deadline)) {
            bobMessages = await bob.loadGroupMessages(groupId);
            if (bobMessages.any(
              (message) =>
                  message.id == laterMessageId && message.text == laterText,
            )) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }

          expect(
            bobMessages.where(
              (message) =>
                  message.id == laterMessageId && message.text == laterText,
            ),
            hasLength(1),
          );
        },
      );

      test(
        'DE-016 validation reject diagnostic stays safe and later fake-network delivery persists',
        () async {
          final admin = GroupTestUser.create(
            peerId: 'admin-de016-validation',
            username: 'Alice',
            network: network,
          );
          final bobDiagnostics = network.registerDiagnosticPeer(
            'reader-de016-validation',
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-de016-validation',
            username: 'Bob',
            network: network,
            groupDiagnosticEvents: bobDiagnostics.stream,
          );
          addTearDown(() {
            admin.dispose();
            bob.dispose();
          });

          const groupId = 'group-de016-validation';
          const laterMessageId = 'de016-valid-network';
          const laterText =
              'DE-016 valid fake-network delivery after validation reject';
          await admin.createGroup(
            groupId: groupId,
            name: 'DE-016 Validation Reject',
          );
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');

          admin.start();
          bob.start();

          final emitted = network.emitValidationRejectedDiagnostic(
            receiverPeerOrDeviceId: bob.deviceId,
            reason: 'non_member',
            groupHash: 'de016-safe-group-hash',
            senderHash: 'de016-safe-sender-hash',
            transportPeerHash: 'de016-safe-transport-hash',
            localPeerHash: 'de016-safe-local-hash',
            keyEpoch: 1,
          );
          expect(emitted, 1);
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(await bob.loadGroupMessages(groupId), isEmpty);

          await admin.sendGroupMessage(
            groupId: groupId,
            text: laterText,
            messageId: laterMessageId,
          );

          final deadline = DateTime.now().add(const Duration(seconds: 2));
          List<GroupMessage> bobMessages = const <GroupMessage>[];
          while (DateTime.now().isBefore(deadline)) {
            bobMessages = await bob.loadGroupMessages(groupId);
            if (bobMessages.any(
              (message) =>
                  message.id == laterMessageId && message.text == laterText,
            )) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }

          expect(
            bobMessages.where(
              (message) =>
                  message.id == laterMessageId && message.text == laterText,
            ),
            hasLength(1),
          );
        },
      );

      test(
        'DE-017 out-of-order membership and content converges to membership interval',
        () async {
          final flowEvents = <Map<String, dynamic>>[];
          debugSetFlowEventSink(flowEvents.add);
          addTearDown(() => debugSetFlowEventSink(null));

          final admin = GroupTestUser.create(
            peerId: 'admin-de017-order',
            username: 'Alice',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-de017-order',
            username: 'Bob',
            network: network,
          );
          final charlie = GroupTestUser.create(
            peerId: 'charlie-de017-order',
            username: 'Charlie',
            network: network,
          );
          addTearDown(() {
            admin.dispose();
            bob.dispose();
            charlie.dispose();
          });

          const groupId = 'group-de017-order';
          await admin.createGroup(
            groupId: groupId,
            name: 'DE-017 Membership Order',
          );
          await admin.addMember(groupId: groupId, invitee: bob);
          final bobMember = await bob.groupRepo.getMember(groupId, bob.peerId);
          final addAt = bobMember!.joinedAt.toUtc().add(
            const Duration(seconds: 2),
          );
          final removalAt = addAt.add(const Duration(seconds: 3));
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');
          await _saveKey(charlie, groupId, 1, 'k1');

          admin.start();
          bob.start();
          charlie.start();

          await network.publish(groupId, charlie.peerId, {
            'groupId': groupId,
            'senderId': charlie.peerId,
            'senderUsername': charlie.username,
            'keyEpoch': 1,
            'text': 'DE-017 pre-join fake-network content',
            'timestamp': addAt
                .subtract(const Duration(seconds: 1))
                .toIso8601String(),
            'messageId': 'de017-fake-pre-join',
          }, senderDeviceId: charlie.deviceId);
          await network.publish(groupId, charlie.peerId, {
            'groupId': groupId,
            'senderId': charlie.peerId,
            'senderUsername': charlie.username,
            'keyEpoch': 1,
            'text': 'DE-017 post-add fake-network content',
            'timestamp': addAt
                .add(const Duration(seconds: 1))
                .toIso8601String(),
            'messageId': 'de017-fake-post-add',
          }, senderDeviceId: charlie.deviceId);

          await Future<void>.delayed(const Duration(milliseconds: 75));
          expect(await bob.msgRepo.getMessage('de017-fake-pre-join'), isNull);
          expect(await bob.msgRepo.getMessage('de017-fake-post-add'), isNull);

          await admin.addMember(
            groupId: groupId,
            invitee: charlie,
            joinedAt: addAt,
          );
          await admin.broadcastMemberAdded(
            groupId: groupId,
            newMember: charlie,
            eventAt: addAt,
          );

          final addDeadline = DateTime.now().add(const Duration(seconds: 2));
          while (DateTime.now().isBefore(addDeadline) &&
              await bob.msgRepo.getMessage('de017-fake-post-add') == null) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }

          expect(await bob.msgRepo.getMessage('de017-fake-pre-join'), isNull);
          final postAdd = await bob.msgRepo.getMessage('de017-fake-post-add');
          expect(postAdd, isNotNull);
          expect(postAdd!.text, 'DE-017 post-add fake-network content');

          await network.publish(groupId, charlie.peerId, {
            'groupId': groupId,
            'senderId': charlie.peerId,
            'senderUsername': charlie.username,
            'keyEpoch': 1,
            'text': 'DE-017 pre-removal fake-network content',
            'timestamp': removalAt
                .subtract(const Duration(seconds: 1))
                .toIso8601String(),
            'messageId': 'de017-fake-pre-removal',
          }, senderDeviceId: charlie.deviceId);
          await network.publish(groupId, charlie.peerId, {
            'groupId': groupId,
            'senderId': charlie.peerId,
            'senderUsername': charlie.username,
            'keyEpoch': 1,
            'text': 'DE-017 post-removal fake-network content',
            'timestamp': removalAt
                .add(const Duration(seconds: 1))
                .toIso8601String(),
            'messageId': 'de017-fake-post-removal',
          }, senderDeviceId: charlie.deviceId);

          final removalPreconditionDeadline = DateTime.now().add(
            const Duration(seconds: 2),
          );
          while (DateTime.now().isBefore(removalPreconditionDeadline) &&
              await bob.msgRepo.getMessage('de017-fake-post-removal') == null) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
          expect(
            await bob.msgRepo.getMessage('de017-fake-pre-removal'),
            isNotNull,
          );
          expect(
            await bob.msgRepo.getMessage('de017-fake-post-removal'),
            isNotNull,
          );

          await admin.removeMember(
            groupId: groupId,
            memberPeerId: charlie.peerId,
            memberUsername: charlie.username,
            removedAt: removalAt,
          );

          final removalDeadline = DateTime.now().add(
            const Duration(seconds: 2),
          );
          while (DateTime.now().isBefore(removalDeadline) &&
              await bob.msgRepo.getMessage('de017-fake-post-removal') != null) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }

          expect(
            await bob.groupRepo.getMember(groupId, charlie.peerId),
            isNull,
          );
          expect(
            await bob.msgRepo.getMessage('de017-fake-pre-removal'),
            isNotNull,
          );
          expect(
            await bob.msgRepo.getMessage('de017-fake-post-removal'),
            isNull,
          );

          final eventNames = flowEvents
              .map((event) => event['event'] as String)
              .toList(growable: false);
          expect(
            eventNames,
            containsAll([
              'GROUP_MESSAGE_LISTENER_MEMBERSHIP_DEPENDENT_CONTENT_BUFFERED',
              'GROUP_MESSAGE_LISTENER_MEMBERSHIP_DEPENDENT_CONTENT_FLUSHED',
              'GROUP_HANDLE_INCOMING_MSG_SENDER_BEFORE_JOINED_REJECTED',
              'GROUP_MESSAGE_LISTENER_MEMBERSHIP_DEPENDENT_CONTENT_REPAIRED',
            ]),
          );
        },
      );

      test(
        'DE-020 large payload does not starve later fake-network delivery',
        () async {
          final admin = GroupTestUser.create(
            peerId: 'admin-de020-large',
            username: 'Alice',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-de020-large',
            username: 'Bob',
            network: network,
          );
          addTearDown(() {
            admin.dispose();
            bob.dispose();
          });

          const groupId = 'group-de020-large';
          const largeMessageId = 'de020-large-network';
          const normalMessageId = 'de020-normal-network';
          const normalText = 'DE-020 normal fake-network follow-up';
          final largeText = 'L' * maxMessageLength;
          await admin.createGroup(groupId: groupId, name: 'DE-020 Large');
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');

          admin.start();
          bob.start();

          await admin.sendGroupMessage(
            groupId: groupId,
            text: largeText,
            messageId: largeMessageId,
          );
          await admin.sendGroupMessage(
            groupId: groupId,
            text: normalText,
            messageId: normalMessageId,
          );

          final deadline = DateTime.now().add(const Duration(seconds: 2));
          List<GroupMessage> bobMessages = const <GroupMessage>[];
          while (DateTime.now().isBefore(deadline)) {
            bobMessages = await bob.loadGroupMessages(groupId);
            final messageIds = bobMessages.map((message) => message.id).toSet();
            if (messageIds.contains(largeMessageId) &&
                messageIds.contains(normalMessageId)) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }

          final largeRows = bobMessages.where(
            (message) =>
                message.id == largeMessageId &&
                message.text.length == maxMessageLength,
          );
          final normalRows = bobMessages.where(
            (message) =>
                message.id == normalMessageId && message.text == normalText,
          );
          expect(largeRows, hasLength(1));
          expect(normalRows, hasLength(1));
          expect(
            bobMessages.indexWhere((message) => message.id == largeMessageId),
            lessThan(
              bobMessages.indexWhere(
                (message) => message.id == normalMessageId,
              ),
            ),
          );
          expect(network.publishCallCount, 2);
          expect(network.totalDeliveries, 2);
        },
      );

      test(
        'DE-003 caller-supplied message id survives live replay and retry',
        () async {
          final adminBridge = _Section10MirroringBridge(
            network: network,
            msgRepo: InMemoryGroupMessageRepository(),
            groupRepo: InMemoryGroupRepository(),
          );
          final bobBridge = _CursorInboxBridge();
          final admin = GroupTestUser.create(
            peerId: 'admin-de003-peer',
            username: 'Alice',
            network: network,
            bridge: adminBridge,
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-de003-bob-peer',
            username: 'Bob',
            network: network,
            bridge: bobBridge,
          );
          final charlie = GroupTestUser.create(
            peerId: 'reader-de003-charlie-peer',
            username: 'Charlie',
            network: network,
          );
          addTearDown(() {
            admin.dispose();
            bob.dispose();
            charlie.dispose();
          });

          const groupId = 'group-de003-stable-id';
          const liveMessageId = 'de003-live-stable-id';
          const retryMessageId = 'de003-retry-stable-id';
          const liveText = 'DE-003 live and replay stable id';
          const retryText = 'DE-003 retry stable id';

          await admin.createGroup(groupId: groupId, name: 'DE-003 Stable Id');
          await admin.addMember(groupId: groupId, invitee: bob);
          await admin.addMember(groupId: groupId, invitee: charlie);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');
          await _saveKey(charlie, groupId, 1, 'k1');

          admin.start();
          bob.start();
          charlie.start();

          final (liveResult, liveSent) = await admin.sendGroupMessageViaBridge(
            groupId: groupId,
            text: liveText,
            messageId: liveMessageId,
          );
          expect(liveResult, SendGroupMessageResult.success);
          expect(liveSent, isNotNull);
          expect(liveSent!.id, liveMessageId);
          expect(
            (await admin.msgRepo.getMessage(liveMessageId))!.id,
            liveMessageId,
          );

          final livePublishPayload = latestBridgePayload(
            adminBridge,
            'group:publish',
          );
          expect(livePublishPayload['messageId'], liveMessageId);
          final liveInboxPayload = latestBridgePayload(
            adminBridge,
            'group:inboxStore',
          );
          expect(
            _decodedGroupReplayPayload(
              liveInboxPayload['message'] as String,
            )['messageId'],
            liveMessageId,
          );

          await pump();
          for (final recipient in <GroupTestUser>[bob, charlie]) {
            final messages = await recipient.loadGroupMessages(groupId);
            expect(
              messages.where((message) => message.id == liveMessageId),
              hasLength(1),
              reason:
                  '${recipient.username} should receive the live explicit id once',
            );
          }

          _injectInboxMessageFromLatestStore(
            senderBridge: adminBridge,
            receiverBridge: bobBridge,
            receiverPeerId: bob.peerId,
            groupId: groupId,
          );
          await drainGroupOfflineInbox(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            msgRepo: bob.msgRepo,
          );
          final bobAfterReplay = await bob.loadGroupMessages(groupId);
          expect(
            bobAfterReplay.where((message) => message.id == liveMessageId),
            hasLength(1),
            reason: 'Duplicate replay must dedupe by caller-supplied id',
          );

          adminBridge.publishFailuresRemaining = 1;
          final (initialRetryResult, initialRetryMessage) = await admin
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: retryText,
                messageId: retryMessageId,
              );
          expect(initialRetryResult, SendGroupMessageResult.error);
          expect(initialRetryMessage, isNotNull);
          expect(initialRetryMessage!.id, retryMessageId);
          expect(initialRetryMessage.status, 'failed');

          final failedRow = await admin.msgRepo.getMessage(retryMessageId);
          expect(failedRow, isNotNull);
          expect(failedRow!.wireEnvelope, isNotNull);
          expect(
            (jsonDecode(failedRow.wireEnvelope!)
                as Map<String, dynamic>)['messageId'],
            retryMessageId,
          );

          final retryPublishPayloads = bridgePayloads(
            adminBridge,
            'group:publish',
          ).where((payload) => payload['messageId'] == retryMessageId).toList();
          expect(retryPublishPayloads, hasLength(1));

          final retried = await retryFailedGroupMessages(
            groupMsgRepo: admin.msgRepo,
            groupRepo: admin.groupRepo,
            identityRepo: _Section10IdentityRepository(_identityForUser(admin)),
            bridge: admin.bridge,
            mediaAttachmentRepo: admin.mediaAttachmentRepo,
          );
          expect(retried, 1);

          final finalMessage = await _latestOutgoingMessage(
            admin.msgRepo,
            groupId,
            text: retryText,
          );
          expect(finalMessage.id, retryMessageId);
          expect(finalMessage.status, 'sent');

          final postRetryPublishPayloads = bridgePayloads(
            adminBridge,
            'group:publish',
          ).where((payload) => payload['messageId'] == retryMessageId).toList();
          expect(postRetryPublishPayloads, hasLength(2));

          await pump();
          for (final recipient in <GroupTestUser>[bob, charlie]) {
            final messages = await recipient.loadGroupMessages(groupId);
            expect(
              messages.where((message) => message.id == retryMessageId),
              hasLength(1),
              reason:
                  '${recipient.username} should receive the retried explicit id once',
            );
          }
        },
      );

      test(
        'unread count stays correct across duplicate inbox drain, retry recovery, and read clear',
        () async {
          final adminBridge = _Section10MirroringBridge(
            network: network,
            msgRepo: InMemoryGroupMessageRepository(),
            groupRepo: InMemoryGroupRepository(),
          );
          final admin = GroupTestUser.create(
            peerId: 'admin-unread-peer',
            username: 'Alice',
            network: network,
            bridge: adminBridge,
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-unread-peer',
            username: 'Bob',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final bobBridge = bob.bridge as _CursorInboxBridge;

          const groupId = 'group-unread-005';
          await admin.createGroup(groupId: groupId, name: 'Unread Accuracy');
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');

          admin.start();
          bob.start();

          final (firstResult, firstMessage) = await admin
              .sendGroupMessageViaBridge(groupId: groupId, text: 'Live once');

          expect(firstResult, SendGroupMessageResult.success);
          expect(firstMessage, isNotNull);

          await pump();
          expect(await bob.msgRepo.getUnreadCount(groupId), 1);
          var summary = await bob.msgRepo.getGroupThreadSummary(groupId);
          expect(summary.unreadCount, 1);
          expect(summary.latestMessage?.text, 'Live once');

          _injectInboxMessageFromLatestStore(
            senderBridge: admin.bridge,
            receiverBridge: bobBridge,
            receiverPeerId: bob.peerId,
            groupId: groupId,
          );
          await drainGroupOfflineInbox(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            msgRepo: bob.msgRepo,
          );

          await pump();
          final bobAfterDuplicate = await bob.loadGroupMessages(groupId);
          expect(
            bobAfterDuplicate.where(
              (message) => message.id == firstMessage!.id && message.isIncoming,
            ),
            hasLength(1),
            reason: 'Duplicate inbox drain must not create a second unread row',
          );
          expect(
            await bob.msgRepo.getUnreadCount(groupId),
            1,
            reason: 'Duplicate recovery must not double-count unread state',
          );

          adminBridge.publishFailuresRemaining = 1;
          final (retryInitialResult, retryInitialMessage) = await admin
              .sendGroupMessageViaBridge(groupId: groupId, text: 'Retry once');

          expect(retryInitialResult, SendGroupMessageResult.error);
          expect(retryInitialMessage, isNotNull);
          expect(retryInitialMessage!.status, 'failed');
          expect(
            await bob.msgRepo.getUnreadCount(groupId),
            1,
            reason: 'Unread must not change until retry actually delivers',
          );

          final retried = await retryFailedGroupMessages(
            groupMsgRepo: admin.msgRepo,
            groupRepo: admin.groupRepo,
            identityRepo: _Section10IdentityRepository(_identityForUser(admin)),
            bridge: admin.bridge,
            mediaAttachmentRepo: admin.mediaAttachmentRepo,
          );

          expect(retried, 1);

          final finalMessage = await _latestOutgoingMessage(
            admin.msgRepo,
            groupId,
            text: 'Retry once',
          );
          expect(finalMessage.id, retryInitialMessage.id);
          expect(finalMessage.status, 'sent');

          await pump();
          final bobAfterRetry = await bob.loadGroupMessages(groupId);
          expect(
            bobAfterRetry.where(
              (message) =>
                  message.id == retryInitialMessage.id && message.isIncoming,
            ),
            hasLength(1),
            reason: 'Successful retry should arrive once for the receiver',
          );
          expect(await bob.msgRepo.getUnreadCount(groupId), 2);
          summary = await bob.msgRepo.getGroupThreadSummary(groupId);
          expect(summary.unreadCount, 2);
          expect(summary.latestMessage?.text, 'Retry once');

          await bob.msgRepo.markAsRead(groupId);

          expect(await bob.msgRepo.getUnreadCount(groupId), 0);
          summary = await bob.msgRepo.getGroupThreadSummary(groupId);
          expect(summary.unreadCount, 0);

          admin.dispose();
          bob.dispose();
        },
      );

      test(
        'IR-020 local delete prevents fake-network inbox resurrection',
        () async {
          final adminBridge = _Section10MirroringBridge(
            network: network,
            msgRepo: InMemoryGroupMessageRepository(),
            groupRepo: InMemoryGroupRepository(),
          );
          final admin = GroupTestUser.create(
            peerId: 'admin-ir020-peer',
            username: 'Alice',
            network: network,
            bridge: adminBridge,
          );
          final bob = GroupTestUser.create(
            peerId: 'reader-ir020-peer',
            username: 'Bob',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final bobBridge = bob.bridge as _CursorInboxBridge;

          const groupId = 'group-ir020-local-delete';
          await admin.createGroup(groupId: groupId, name: 'IR020 Local Delete');
          await admin.addMember(groupId: groupId, invitee: bob);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');

          admin.start();
          bob.start();

          final (sendResult, sentMessage) = await admin
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: 'Delete locally before replay',
              );
          expect(sendResult, SendGroupMessageResult.success);
          expect(sentMessage, isNotNull);

          await pump();
          expect(await bob.msgRepo.getMessage(sentMessage!.id), isNotNull);
          expect(await bob.msgRepo.getUnreadCount(groupId), 1);

          await bob.msgRepo.deleteMessage(sentMessage.id);

          expect(await bob.msgRepo.getMessage(sentMessage.id), isNull);
          expect(await bob.msgRepo.getMessageCount(groupId), 0);
          expect(await bob.msgRepo.getUnreadCount(groupId), 0);

          _injectInboxMessageFromLatestStore(
            senderBridge: admin.bridge,
            receiverBridge: bobBridge,
            receiverPeerId: bob.peerId,
            groupId: groupId,
          );
          await drainGroupOfflineInbox(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            msgRepo: bob.msgRepo,
          );

          await pump();
          final bobAfterReplay = await bob.loadGroupMessages(groupId);
          expect(
            bobAfterReplay.where((message) => message.id == sentMessage.id),
            isEmpty,
          );
          expect(await bob.msgRepo.getMessage(sentMessage.id), isNull);
          expect(await bob.msgRepo.getUnreadCount(groupId), 0);
          final summary = await bob.msgRepo.getGroupThreadSummary(groupId);
          expect(summary.unreadCount, 0);
          expect(summary.latestMessage, isNull);

          admin.dispose();
          bob.dispose();
        },
      );

      test(
        'NW-010 background pause resumes ordered group delivery after membership edit',
        () async {
          final trace = <String>[];
          final bobBridge = _RejoiningCursorInboxBridge(
            network: network,
            peerId: 'bob-nw010-background-peer',
            trace: trace,
          );
          final alice = GroupTestUser.create(
            peerId: 'alice-nw010-background-peer',
            username: 'Alice',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'bob-nw010-background-peer',
            username: 'Bob',
            network: network,
            bridge: bobBridge,
          );
          final charlie = GroupTestUser.create(
            peerId: 'charlie-nw010-background-peer',
            username: 'Charlie',
            network: network,
          );
          const groupId = 'group-nw010-background-resume';
          const baselineText = 'NW-010 baseline before background';
          const missedBeforeEditText = 'NW-010 missed before membership edit';
          const missedAfterEditText = 'NW-010 missed after membership edit';
          const postResumeText = 'NW-010 Alice live after foreground';
          const bobPublishText = 'NW-010 Bob publish after foreground';
          late final DateTime baseTime;
          late final DateTime removalAt;

          Future<Set<String>> incomingTexts(GroupTestUser user) async {
            return (await user.loadGroupMessages(groupId))
                .where((message) => message.isIncoming)
                .map((message) => message.text)
                .toSet();
          }

          Future<Set<String>> memberPeerIds(GroupTestUser user) async {
            return (await user.groupRepo.getMembers(
              groupId,
            )).map((member) => member.peerId).toSet();
          }

          Map<String, dynamic> relayFromInboxPayload(
            Map<String, dynamic> inboxPayload,
          ) {
            final storedMessage = inboxPayload['message'] as String;
            final decodedPayload = _decodedGroupReplayPayload(storedMessage);
            return <String, dynamic>{
              'from': decodedPayload['senderId'] as String? ?? alice.peerId,
              'message': storedMessage,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            };
          }

          Future<Map<String, dynamic>> memberRemovedReplay() async {
            final group = await alice.groupRepo.getGroup(groupId);
            final members = await alice.groupRepo.getMembers(groupId);
            final groupConfig = <String, dynamic>{
              'name': group!.name,
              'groupType': group.type.toValue(),
              if (group.description != null) 'description': group.description,
              'members': members
                  .map((member) => member.toConfigJson())
                  .toList(growable: false),
              'createdBy': group.createdBy,
              'createdAt': group.createdAt.toUtc().toIso8601String(),
            };
            return _signedReplayRelayMessage(
              bridge: alice.bridge,
              groupRepo: alice.groupRepo,
              groupId: groupId,
              payload: <String, dynamic>{
                'groupId': groupId,
                'senderId': alice.peerId,
                'senderUsername': alice.username,
                'keyEpoch': 1,
                'text': jsonEncode(<String, dynamic>{
                  '__sys': 'member_removed',
                  'member': <String, dynamic>{
                    'peerId': charlie.peerId,
                    'username': 'Charlie',
                  },
                  'removedAt': removalAt.toIso8601String(),
                  'groupConfig': groupConfig,
                }),
                'timestamp': removalAt.toIso8601String(),
                'messageId': 'nw010-remove-charlie',
              },
              senderPeerId: alice.peerId,
              senderPublicKey: alice.publicKey,
              senderPrivateKey: alice.privateKey,
            );
          }

          try {
            await alice.createGroup(groupId: groupId, name: 'NW-010');
            await alice.addMember(groupId: groupId, invitee: bob);
            await alice.addMember(groupId: groupId, invitee: charlie);
            await _saveKey(alice, groupId, 1, 'nw010-key');
            await _saveKey(bob, groupId, 1, 'nw010-key');
            await _saveKey(charlie, groupId, 1, 'nw010-key');
            for (final member in await alice.groupRepo.getMembers(groupId)) {
              await bob.groupRepo.saveMember(member);
            }
            baseTime = DateTime.now().toUtc().subtract(
              const Duration(seconds: 5),
            );
            removalAt = DateTime.now().toUtc();

            alice.start();
            bob.start();
            charlie.start();

            await alice.broadcastMemberAdded(
              groupId: groupId,
              newMember: charlie,
              eventAt: baseTime,
            );
            await pumpUntilAsync(() async {
              return (await memberPeerIds(bob)).contains(charlie.peerId);
            }, maxPumps: 80);

            await alice.sendGroupMessage(
              groupId: groupId,
              text: baselineText,
              messageId: 'nw010-baseline',
              timestamp: baseTime,
            );
            await pumpUntilAsync(() async {
              return (await incomingTexts(bob)).contains(baselineText) &&
                  (await incomingTexts(charlie)).contains(baselineText);
            }, maxPumps: 80);

            network.unsubscribe(groupId, bob.peerId);
            expect(network.isSubscribed(groupId, bob.peerId), isFalse);

            final (beforeResult, beforeMessage) = await alice
                .sendGroupMessageViaBridge(
                  groupId: groupId,
                  text: missedBeforeEditText,
                  messageId: 'nw010-missed-before-edit',
                  timestamp: baseTime.add(const Duration(seconds: 1)),
                );
            expect(beforeResult, SendGroupMessageResult.success);
            expect(beforeMessage, isNotNull);
            final beforeStore = latestBridgePayload(
              alice.bridge,
              'group:inboxStore',
            );
            await pumpUntilAsync(() async {
              return (await incomingTexts(
                charlie,
              )).contains(missedBeforeEditText);
            }, maxPumps: 80);
            expect(
              await incomingTexts(bob),
              isNot(contains(missedBeforeEditText)),
              reason: 'Bob must not receive live traffic while backgrounded',
            );

            await alice.removeMember(
              groupId: groupId,
              memberPeerId: charlie.peerId,
              memberUsername: 'Charlie',
              removedAt: removalAt,
            );
            await pump();
            final removalReplay = await memberRemovedReplay();

            final (afterResult, afterMessage) = await alice
                .sendGroupMessageViaBridge(
                  groupId: groupId,
                  text: missedAfterEditText,
                  messageId: 'nw010-missed-after-edit',
                  timestamp: DateTime.now().toUtc(),
                );
            expect(afterResult, SendGroupMessageResult.successNoPeers);
            expect(afterMessage, isNotNull);
            final afterStore = latestBridgePayload(
              alice.bridge,
              'group:inboxStore',
            );
            final afterRecipients =
                (afterStore['recipientPeerIds'] as List<dynamic>)
                    .cast<String>();
            expect(afterRecipients, contains(bob.peerId));
            expect(afterRecipients, isNot(contains(charlie.peerId)));

            bobBridge.addPage(groupId, '', [
              relayFromInboxPayload(beforeStore),
              removalReplay,
              relayFromInboxPayload(afterStore),
              relayFromInboxPayload(beforeStore),
            ], '');

            expect(
              await incomingTexts(bob),
              isNot(contains(missedAfterEditText)),
            );
            expect(await memberPeerIds(bob), contains(charlie.peerId));

            final rejoinResult = await rejoinGroupTopics(
              bridge: bob.bridge,
              groupRepo: bob.groupRepo,
              reason: RejoinReason.nodeRequestedRecovery,
            );
            expect(rejoinResult.errorCount, 0);
            final drainResult = await drainGroupOfflineInbox(
              bridge: bob.bridge,
              groupRepo: bob.groupRepo,
              msgRepo: bob.msgRepo,
              groupMessageListener: bob.groupMessageListener,
              selfPeerId: bob.peerId,
            );
            expect(drainResult.isSuccessful, isTrue);
            await callGroupAcknowledgeRecovery(bob.bridge);
            expect(network.isSubscribed(groupId, bob.peerId), isTrue);

            final bobMessagesAfterDrain = await bob.loadGroupMessages(groupId);
            expect(
              bobMessagesAfterDrain.where(
                (message) =>
                    message.text == missedBeforeEditText && message.isIncoming,
              ),
              hasLength(1),
            );
            expect(
              bobMessagesAfterDrain.where(
                (message) =>
                    message.text == missedAfterEditText && message.isIncoming,
              ),
              hasLength(1),
            );
            final bobTextsAfterDrain = bobMessagesAfterDrain
                .map((message) => message.text)
                .toList();
            final beforeIndex = bobTextsAfterDrain.indexOf(
              missedBeforeEditText,
            );
            final removalIndex = bobTextsAfterDrain.indexOf(
              'Alice removed Charlie',
            );
            final afterIndex = bobTextsAfterDrain.indexOf(missedAfterEditText);
            expect(beforeIndex, isNot(-1));
            expect(removalIndex, isNot(-1));
            expect(afterIndex, isNot(-1));
            expect(beforeIndex, lessThan(removalIndex));
            expect(removalIndex, lessThan(afterIndex));

            final expectedMembers = {alice.peerId, bob.peerId};
            expect(await memberPeerIds(alice), expectedMembers);
            expect(await memberPeerIds(bob), expectedMembers);
            expect(
              (await alice.groupRepo.getLatestKey(groupId))!.keyGeneration,
              (await bob.groupRepo.getLatestKey(groupId))!.keyGeneration,
            );
            expect(trace, contains('join:$groupId'));
            expect(trace, contains('drain:$groupId'));
            expect(trace, contains('ack'));

            await alice.sendGroupMessage(
              groupId: groupId,
              text: postResumeText,
              messageId: 'nw010-alice-live-after-foreground',
              timestamp: DateTime.now().toUtc(),
            );
            await bob.sendGroupMessage(
              groupId: groupId,
              text: bobPublishText,
              messageId: 'nw010-bob-publish-after-foreground',
              timestamp: DateTime.now().toUtc(),
            );
            await pumpUntilAsync(() async {
              return (await incomingTexts(bob)).contains(postResumeText) &&
                  (await incomingTexts(alice)).contains(bobPublishText);
            }, maxPumps: 120);
            expect(
              await incomingTexts(charlie),
              isNot(contains(bobPublishText)),
            );
          } finally {
            alice.dispose();
            bob.dispose();
            charlie.dispose();
          }
        },
      );

      test(
        'offline member reconnects after membership churn and converges to the final member list',
        () async {
          final admin = GroupTestUser.create(
            peerId: 'admin-converge-peer',
            username: 'Admin',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'bob-converge-peer',
            username: 'Bob',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final charlie = GroupTestUser.create(
            peerId: 'charlie-converge-peer',
            username: 'Charlie',
            network: network,
          );
          final diana = GroupTestUser.create(
            peerId: 'diana-converge-peer',
            username: 'Diana',
            network: network,
          );
          final bobBridge = bob.bridge as _CursorInboxBridge;

          const groupId = 'group-member-converge-010';

          Future<Map<String, dynamic>> membershipReplayEnvelope({
            required String systemType,
            required Map<String, dynamic> member,
          }) async {
            final group = await admin.groupRepo.getGroup(groupId);
            final members = await admin.groupRepo.getMembers(groupId);
            final groupConfig = {
              'name': group!.name,
              'groupType': group.type.toValue(),
              if (group.description != null) 'description': group.description,
              'members': members
                  .map(
                    (entry) => {
                      'peerId': entry.peerId,
                      'username': entry.username,
                      'role': entry.role.toValue(),
                      'publicKey': entry.publicKey,
                    },
                  )
                  .toList(),
              'createdBy': group.createdBy,
              'createdAt': group.createdAt.toUtc().toIso8601String(),
            };

            final replayPayload = {
              'groupId': groupId,
              'senderId': admin.peerId,
              'senderUsername': admin.username,
              'keyEpoch': 0,
              'text': jsonEncode({
                '__sys': systemType,
                'member': member,
                'groupConfig': groupConfig,
              }),
              'timestamp': DateTime.now().toUtc().toIso8601String(),
            };
            return _signedReplayRelayMessage(
              bridge: admin.bridge,
              groupRepo: admin.groupRepo,
              groupId: groupId,
              payload: replayPayload,
              senderPeerId: admin.peerId,
              senderPublicKey: admin.publicKey,
              senderPrivateKey: admin.privateKey,
            );
          }

          Map<String, String> memberRoleMap(List<GroupMember> members) {
            return {
              for (final member in members)
                member.peerId: member.role.toValue(),
            };
          }

          await admin.createGroup(groupId: groupId, name: 'Reconnect Churn');
          await admin.addMember(groupId: groupId, invitee: bob);
          await admin.addMember(groupId: groupId, invitee: charlie);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');
          await _saveKey(charlie, groupId, 1, 'k1');

          admin.start();
          bob.start();
          charlie.start();
          await admin.broadcastMemberAdded(
            groupId: groupId,
            newMember: charlie,
          );
          await pump();

          network.unsubscribe(groupId, bob.peerId);

          await admin.removeMember(
            groupId: groupId,
            memberPeerId: charlie.peerId,
            memberUsername: 'Charlie',
          );
          final removedEnvelope = await membershipReplayEnvelope(
            systemType: 'member_removed',
            member: {'peerId': charlie.peerId, 'username': 'Charlie'},
          );
          await pump();

          await admin.addMember(groupId: groupId, invitee: diana);
          await _saveKey(diana, groupId, 1, 'k1');
          final addedEnvelope = await membershipReplayEnvelope(
            systemType: 'member_added',
            member: {
              'peerId': diana.peerId,
              'username': 'Diana',
              'role': 'writer',
              'publicKey': diana.publicKey,
            },
          );
          await admin.broadcastMemberAdded(groupId: groupId, newMember: diana);
          await pump();

          final staleBobMembers = await bob.groupRepo.getMembers(groupId);
          expect(
            staleBobMembers.map((member) => member.peerId).toSet(),
            contains(charlie.peerId),
          );
          expect(
            staleBobMembers.map((member) => member.peerId).toSet(),
            isNot(contains(diana.peerId)),
          );

          bobBridge.addPage(groupId, '', [removedEnvelope, addedEnvelope], '');

          await rejoinGroupTopics(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            reason: RejoinReason.startup,
          );
          network.subscribe(groupId, bob.peerId);
          await drainGroupOfflineInbox(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            msgRepo: bob.msgRepo,
            groupMessageListener: bob.groupMessageListener,
          );

          final adminMembers = await admin.groupRepo.getMembers(groupId);
          final bobMembers = await bob.groupRepo.getMembers(groupId);
          final dianaMembers = await diana.groupRepo.getMembers(groupId);

          expect(memberRoleMap(bobMembers), memberRoleMap(adminMembers));
          expect(memberRoleMap(dianaMembers), memberRoleMap(adminMembers));
          expect(memberRoleMap(adminMembers).keys.toSet(), {
            admin.peerId,
            bob.peerId,
            diana.peerId,
          });

          final adminGroup = await admin.groupRepo.getGroup(groupId);
          final bobGroup = await bob.groupRepo.getGroup(groupId);
          final dianaGroup = await diana.groupRepo.getGroup(groupId);

          expect(bobGroup, isNotNull);
          expect(dianaGroup, isNotNull);
          expect(bobGroup!.name, adminGroup!.name);
          expect(bobGroup.type, adminGroup.type);
          expect(bobGroup.createdBy, adminGroup.createdBy);
          expect(dianaGroup!.name, adminGroup.name);
          expect(dianaGroup.type, adminGroup.type);
          expect(dianaGroup.createdBy, adminGroup.createdBy);

          admin.dispose();
          bob.dispose();
          charlie.dispose();
          diana.dispose();
        },
      );

      test(
        'offline member reconnects after repeated metadata edits and converges to the final metadata state',
        () async {
          final admin = GroupTestUser.create(
            peerId: 'admin-meta-peer',
            username: 'Admin',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'bob-meta-peer',
            username: 'Bob',
            network: network,
            bridge: _CursorInboxBridge(),
          );
          final charlie = GroupTestUser.create(
            peerId: 'charlie-meta-peer',
            username: 'Charlie',
            network: network,
          );
          final bobBridge = bob.bridge as _CursorInboxBridge;
          admin.bridge.responses['payload.sign'] = {
            'ok': true,
            'signature': 'sig-metadata-converge',
          };
          bob.bridge.responses['payload.verify'] = {'ok': true, 'valid': true};
          charlie.bridge.responses['payload.verify'] = {
            'ok': true,
            'valid': true,
          };

          const groupId = 'group-metadata-converge-011';
          await admin.createGroup(
            groupId: groupId,
            name: 'Metadata Start',
            description: 'Original description',
          );
          await admin.addMember(groupId: groupId, invitee: bob);
          await admin.addMember(groupId: groupId, invitee: charlie);
          await _saveKey(admin, groupId, 1, 'k1');
          await _saveKey(bob, groupId, 1, 'k1');
          await _saveKey(charlie, groupId, 1, 'k1');

          admin.start();
          bob.start();
          charlie.start();

          network.unsubscribe(groupId, bob.peerId);

          Future<Map<String, dynamic>> publishMetadataUpdate({
            required String messageId,
            required DateTime eventAt,
            required String name,
            required String description,
          }) async {
            final updatedGroup = await updateGroupMetadata(
              groupRepo: admin.groupRepo,
              groupId: groupId,
              name: name,
              description: description,
              eventAt: eventAt,
            );
            final members = await admin.groupRepo.getMembers(groupId);
            final groupConfig = buildGroupConfigPayload(updatedGroup, members);
            final actorPayload = buildGroupMetadataActorEventPayload(
              groupId: groupId,
              updatedAt: eventAt,
              actorPeerId: admin.peerId,
              actorUsername: admin.username,
              actorPublicKey: admin.publicKey,
              groupConfig: groupConfig,
            );
            final canonicalPayload = canonicalizeGroupMetadataActorEventPayload(
              actorPayload,
            );
            final signResponse = await callSignPayload(
              bridge: admin.bridge,
              dataToSign: canonicalPayload,
              privateKey: admin.privateKey,
            );
            final signature = signResponse['signature'];
            if (signResponse['ok'] != true ||
                signature is! String ||
                signature.isEmpty) {
              throw StateError('Failed to sign group metadata update fixture');
            }
            final updatedAtIso = eventAt.toUtc().toIso8601String();
            final sysText = jsonEncode({
              '__sys': 'group_metadata_updated',
              'updatedAt': updatedAtIso,
              'groupConfig': groupConfig,
              groupMetadataActorEventEnvelopeField:
                  buildSignedGroupMetadataActorEventEnvelope(
                    signedPayload: canonicalPayload,
                    signature: signature,
                  ),
            });
            final envelope = <String, dynamic>{
              'groupId': groupId,
              'senderId': admin.peerId,
              'senderUsername': admin.username,
              'keyEpoch': 0,
              'text': sysText,
              'timestamp': updatedAtIso,
              'messageId': messageId,
            };
            await network.publish(groupId, admin.peerId, envelope);
            return _signedReplayRelayMessage(
              bridge: admin.bridge,
              groupRepo: admin.groupRepo,
              groupId: groupId,
              payload: envelope,
              senderPeerId: admin.peerId,
              senderPublicKey: admin.publicKey,
              senderPrivateKey: admin.privateKey,
            );
          }

          final olderAt = DateTime.parse('2026-04-05T13:00:00.000Z').toUtc();
          final newerAt = DateTime.parse('2026-04-05T13:05:00.000Z').toUtc();

          final olderEnvelope = await publishMetadataUpdate(
            messageId: 'msg-meta-older',
            eventAt: olderAt,
            name: 'Planning Alpha',
            description: 'First draft',
          );
          await pump();

          final newerEnvelope = await publishMetadataUpdate(
            messageId: 'msg-meta-newer',
            eventAt: newerAt,
            name: 'Planning Final',
            description: 'Final charter',
          );
          await pump();

          final livePeerGroup = await charlie.groupRepo.getGroup(groupId);
          expect(livePeerGroup, isNotNull);
          expect(livePeerGroup!.name, 'Planning Final');
          expect(livePeerGroup.description, 'Final charter');
          expect(livePeerGroup.lastMetadataEventAt, newerAt);

          final offlineBeforeDrain = await bob.groupRepo.getGroup(groupId);
          expect(offlineBeforeDrain, isNotNull);
          expect(offlineBeforeDrain!.name, 'Metadata Start');
          expect(offlineBeforeDrain.description, 'Original description');

          bobBridge.addPage(groupId, '', [newerEnvelope], 'cursor-older-meta');
          bobBridge.addPage(groupId, 'cursor-older-meta', [olderEnvelope], '');

          await rejoinGroupTopics(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            reason: RejoinReason.startup,
          );
          network.subscribe(groupId, bob.peerId);
          await drainGroupOfflineInbox(
            bridge: bob.bridge,
            groupRepo: bob.groupRepo,
            msgRepo: bob.msgRepo,
            groupMessageListener: bob.groupMessageListener,
          );

          final convergedGroup = await bob.groupRepo.getGroup(groupId);
          expect(convergedGroup, isNotNull);
          expect(convergedGroup!.name, 'Planning Final');
          expect(convergedGroup.description, 'Final charter');
          expect(convergedGroup.lastMetadataEventAt, newerAt);

          final bobMessages = await bob.loadGroupMessages(groupId);
          expect(
            bobMessages.where(
              (message) => message.text == 'Admin updated the group details',
            ),
            hasLength(1),
          );

          admin.dispose();
          bob.dispose();
          charlie.dispose();
        },
      );

      test("multi-group resume doesn't burst", () async {
        final user = GroupTestUser.create(
          peerId: 'user-burst-peer',
          username: 'User',
          network: network,
          bridge: _CursorInboxBridge(),
        );
        final userBridge = user.bridge as _CursorInboxBridge;

        const groupCount = 10;
        final groupIds = List.generate(
          groupCount,
          (index) => 'group-burst-$index',
        );
        for (final groupId in groupIds) {
          await user.createGroup(groupId: groupId, name: 'Burst $groupId');
          await user.groupRepo.saveMember(
            GroupMember(
              groupId: groupId,
              peerId: 'other-peer',
              username: 'Other',
              role: MemberRole.writer,
              publicKey: 'other-peer-pk',
              mlKemPublicKey: 'other-peer-mlkem',
              joinedAt: DateTime.now().toUtc(),
            ),
          );
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: 'key-$groupId',
              createdAt: DateTime.now().toUtc(),
            ),
          );

          final ts = DateTime.now().toUtc().toIso8601String();
          userBridge.addPage(groupId, '', [
            await _signedReplayRelayMessage(
              bridge: user.bridge,
              groupRepo: user.groupRepo,
              groupId: groupId,
              payload: {
                'groupId': groupId,
                'senderId': 'other-peer',
                'senderUsername': 'Other',
                'keyEpoch': 1,
                'text': 'Missed msg in $groupId',
                'timestamp': ts,
                'messageId': 'msg-$groupId',
              },
              senderPeerId: 'other-peer',
              senderPublicKey: 'other-peer-pk',
              senderPrivateKey: 'other-peer-sk',
            ),
          ], '');
        }

        user.start();

        await simulateBackgroundForegroundCycle(
          bridge: user.bridge,
          p2pService: FakeP2PService(),
          messageRepo: InMemoryMessageRepository(),
          groupMsgRepo: user.msgRepo,
          afterResume: () async {
            await drainGroupOfflineInbox(
              bridge: user.bridge,
              groupRepo: user.groupRepo,
              msgRepo: user.msgRepo,
            );
          },
        );

        final retrieveCount = userBridge.commandLog
            .where((command) => command == 'group:inboxRetrieveCursor')
            .length;
        expect(retrieveCount, groupCount);

        for (final groupId in groupIds) {
          final messages = await user.msgRepo.getMessagesPage(groupId);
          expect(
            messages.length,
            1,
            reason: 'Group $groupId should have 1 drained message',
          );
        }

        user.dispose();
      });
    });
  });
}

List<GroupDeliveryExpectation> _ob011SyntheticExpectations({
  required String groupId,
  required GroupTestUser admin,
}) {
  return const <String, String>{
        'ob011-key-miss': ob011CauseKey,
        'ob011-membership-miss': ob011CauseMembership,
        'ob011-replay-miss': ob011CauseReplay,
        'ob011-dispatcher-miss': ob011CauseDispatcher,
        'ob011-ui-filter-miss': ob011CauseUiFilter,
      }.entries
      .map(
        (entry) => GroupDeliveryExpectation(
          groupId: groupId,
          messageId: entry.key,
          senderPeerId: admin.peerId,
          recipientPeerId: 'reader-${entry.value}-ob011',
          keyEpoch: entry.value == ob011CauseKey ? 2 : 1,
          expectedVia: 'canonical_failure_suite',
        ),
      )
      .toList(growable: false);
}

List<Map<String, dynamic>> _ob011SyntheticDiagnostics({
  required String groupId,
}) {
  return <Map<String, dynamic>>[
    _ob011Diagnostic(
      groupId: groupId,
      messageId: 'ob011-key-miss',
      recipientPeerId: 'reader-$ob011CauseKey-ob011',
      event: 'GROUP_DECRYPTION_FAILED',
      cause: ob011CauseKey,
      reason: 'missing_epoch_key',
      resolution: 'key_repair_requested',
    ),
    _ob011Diagnostic(
      groupId: groupId,
      messageId: 'ob011-membership-miss',
      recipientPeerId: 'reader-$ob011CauseMembership-ob011',
      event: 'GROUP_MEMBERSHIP_REJECTED',
      cause: ob011CauseMembership,
      reason: 'removed_member',
    ),
    _ob011Diagnostic(
      groupId: groupId,
      messageId: 'ob011-replay-miss',
      recipientPeerId: 'reader-$ob011CauseReplay-ob011',
      event: 'GROUP_INBOX_REPLAY_CURSOR_GAP',
      cause: ob011CauseReplay,
      reason: 'cursor_gap',
      resolution: 'retry_replay',
    ),
    _ob011Diagnostic(
      groupId: groupId,
      messageId: 'ob011-dispatcher-miss',
      recipientPeerId: 'reader-$ob011CauseDispatcher-ob011',
      event: 'GROUP_DISPATCHER_OVERFLOW_RECOVERY_REQUESTED',
      cause: ob011CauseDispatcher,
      reason: 'dispatcher_overflow',
      resolution: 'overflow_replay_requested',
    ),
    _ob011Diagnostic(
      groupId: groupId,
      messageId: 'ob011-ui-filter-miss',
      recipientPeerId: 'reader-$ob011CauseUiFilter-ob011',
      event: 'GROUP_CONVERSATION_UI_FILTERED_MESSAGE',
      cause: ob011CauseUiFilter,
      reason: 'visibility_filter',
    ),
  ];
}

Map<String, dynamic> _ob011Diagnostic({
  required String groupId,
  required String messageId,
  required String recipientPeerId,
  required String event,
  required String cause,
  required String reason,
  String? resolution,
}) {
  return <String, dynamic>{
    'event': event,
    'groupId': groupId,
    'messageId': messageId,
    'recipientPeerId': recipientPeerId,
    'missedMessageCause': cause,
    'reason': reason,
    'resolution': ?resolution,
  };
}
