import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_key_update_signature.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_backlog_retention_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_history_gap_repair.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_message_receipt.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_repair.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_history_gap_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/fake_notification_service.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';

const _validContentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

final _fixedDateFixtureRetentionNow = DateTime.utc(2026, 5, 8, 12);

/// Bridge that simulates cursor-based group inbox retrieval.
///
/// Stores pages of messages keyed by cursor. Empty string cursor = first page.
/// Each page includes a nextCursor. Empty nextCursor = last page.
class _CursorInboxBridge extends FakeBridge {
  final Map<String, _InboxPage> pages = {};
  Future<Map<String, dynamic>> Function(
    String groupId,
    Map<String, dynamic> message,
  )?
  signLegacyReplayMessage;

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
    if (cmd != null) commandLog.add(cmd);
    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);
    lastCommand = cmd;

    if (cmd == 'group:inboxRetrieveCursor') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      final cursor = payload['cursor'] as String? ?? '';
      final key = '$groupId:$cursor';

      final page = pages[key];
      if (page != null) {
        final messages = <Map<String, dynamic>>[];
        for (final pageMessage in page.messages) {
          messages.add(await _preparePageMessage(groupId, pageMessage));
        }
        return jsonEncode({
          'ok': true,
          'messages': messages,
          'cursor': page.nextCursor,
          if (page.historyGaps.isNotEmpty) 'historyGaps': page.historyGaps,
        });
      }
      // No page found — return empty
      return jsonEncode({
        'ok': true,
        'messages': <Map<String, dynamic>>[],
        'cursor': '',
      });
    }

    if (cmd == 'group:historyRepairRange') {
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

  Future<Map<String, dynamic>> _preparePageMessage(
    String groupId,
    Map<String, dynamic> message,
  ) async {
    if (_isSignedReplayRelayMessage(message)) {
      return message;
    }
    final signer = signLegacyReplayMessage;
    if (signer == null) {
      return message;
    }
    return signer(groupId, Map<String, dynamic>.from(message));
  }

  bool _isSignedReplayRelayMessage(Map<String, dynamic> message) {
    final messageStr = message['message'];
    if (messageStr is! String || messageStr.isEmpty) {
      return false;
    }
    try {
      final decoded = jsonDecode(messageStr);
      return decoded is Map &&
          isGroupOfflineReplayEnvelope(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return false;
    }
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
    final merged = existing.copyWith(
      senderPeerId: repair.senderPeerId,
      transportPeerId: repair.transportPeerId,
      replayEnvelopeJson:
          existing.replayEnvelopeJson ?? repair.replayEnvelopeJson,
      updatedAt: repair.updatedAt,
    );
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
    final pending =
        repairs.values
            .where(
              (repair) =>
                  repair.groupId == groupId &&
                  repair.keyEpoch == keyEpoch &&
                  repair.status == groupPendingKeyRepairStatusPendingKey,
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return pending.take(limit).toList();
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
    if (existing.isTerminal) {
      return GroupHistoryGapRepairUpsertResult(
        repair: existing,
        created: false,
      );
    }
    final merged = existing.copyWith(
      missingAfterMessageId: repair.missingAfterMessageId,
      missingBeforeMessageId: repair.missingBeforeMessageId,
      expectedRangeHash: repair.expectedRangeHash,
      expectedHeadMessageId: repair.expectedHeadMessageId,
      candidateSourcePeerIds: repair.candidateSourcePeerIds,
      updatedAt: repair.updatedAt,
    );
    repairs[key] = merged;
    return GroupHistoryGapRepairUpsertResult(repair: merged, created: false);
  }

  @override
  Future<GroupHistoryGapRepair?> getRepair({
    required String groupId,
    required String gapId,
  }) async {
    return repairs[_key(groupId, gapId)];
  }

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
    final visible =
        repairs.values
            .where(
              (repair) =>
                  repair.groupId == groupId &&
                  repair.status != groupHistoryGapRepairStatusRepaired,
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return visible.take(limit).toList();
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
      failureReason: null,
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

class _TimeoutCursorInboxBridge extends _CursorInboxBridge {
  final Set<String> timeoutPages = {};

  void addTimeout(String groupId, String cursor) {
    timeoutPages.add('$groupId:$cursor');
  }

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:inboxRetrieveCursor') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      final cursor = payload['cursor'] as String? ?? '';
      if (timeoutPages.contains('$groupId:$cursor')) {
        if (cmd != null) commandLog.add(cmd);
        sendCallCount++;
        lastSentMessage = message;
        sentMessages.add(message);
        lastCommand = cmd;
        throw TimeoutException('Simulated cursor timeout');
      }
    }
    return super.send(message);
  }
}

class _SensitiveCursorErrorBridge extends _CursorInboxBridge {
  _SensitiveCursorErrorBridge(this.errorMessage);

  final String errorMessage;

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
      return jsonEncode({
        'ok': false,
        'errorCode': 'SENSITIVE_RELAY_ERROR',
        'errorMessage': errorMessage,
      });
    }
    return super.send(message);
  }
}

class _DelayedCursorInboxBridge extends _CursorInboxBridge {
  final Map<String, Duration> delays = {};

  void addDelay(String groupId, String cursor, Duration delay) {
    delays['$groupId:$cursor'] = delay;
  }

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:inboxRetrieveCursor') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      final cursor = payload['cursor'] as String? ?? '';
      final delay = delays['$groupId:$cursor'];
      if (delay != null) {
        await Future<void>.delayed(delay);
      }
    }
    return super.send(message);
  }
}

void main() {
  late _CursorInboxBridge bridge;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;

  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: '/mknoon/group/group-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-admin',
    myRole: GroupRole.member,
  );

  String? legacyString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Map<String, dynamic>? legacyPayloadFromRelayMessage(
    String pageGroupId,
    Map<String, dynamic> relayMessage,
  ) {
    final messageStr = relayMessage['message'];
    if (messageStr is String && messageStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(messageStr);
        if (decoded is Map) {
          final payload = Map<String, dynamic>.from(decoded);
          if (isGroupOfflineReplayEnvelope(payload)) {
            return null;
          }
          return payload;
        }
      } catch (_) {
        return null;
      }
    }
    if (relayMessage.containsKey('senderId') ||
        relayMessage.containsKey('senderPeerId')) {
      return {'groupId': pageGroupId, ...relayMessage};
    }
    return null;
  }

  Future<void> saveReplayKey(String groupId, int keyGeneration) async {
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: keyGeneration,
        encryptedKey: 'replay-key-$keyGeneration',
        createdAt: DateTime.utc(2026, 5, 2),
      ),
    );
  }

  Future<({String publicKey, String? deviceId, String? transportPeerId})>
  legacySigningIdentity({
    required String groupId,
    required String senderPeerId,
    String? senderDeviceId,
    String? senderTransportPeerId,
  }) async {
    final member = await groupRepo.getMember(groupId, senderPeerId);
    final device =
        member?.findDeviceById(senderDeviceId) ??
        member?.findDeviceByTransportPeerId(senderTransportPeerId) ??
        (member?.activeDevices.isNotEmpty == true
            ? member!.activeDevices.first
            : null);
    final fallbackPublicKey = 'pk-$senderPeerId';
    if (device != null) {
      return (
        publicKey: device.deviceSigningPublicKey,
        deviceId: device.deviceId,
        transportPeerId: device.transportPeerId,
      );
    }
    if (member != null && (member.publicKey?.trim().isEmpty ?? true)) {
      await groupRepo.saveMember(member.copyWith(publicKey: fallbackPublicKey));
    }
    return (
      publicKey: member?.publicKey?.trim().isNotEmpty == true
          ? member!.publicKey!.trim()
          : fallbackPublicKey,
      deviceId: senderDeviceId,
      transportPeerId: senderTransportPeerId,
    );
  }

  Future<Map<String, dynamic>> signedLegacyRelayMessage(
    String pageGroupId,
    Map<String, dynamic> relayMessage,
  ) async {
    final payload = legacyPayloadFromRelayMessage(pageGroupId, relayMessage);
    if (payload == null) {
      return relayMessage;
    }
    final groupId = legacyString(payload['groupId']) ?? pageGroupId;
    final senderPeerId =
        legacyString(payload['senderId']) ??
        legacyString(payload['senderPeerId']) ??
        legacyString(relayMessage['from']) ??
        'peer-sender';
    final keyGeneration = payload['keyEpoch'] is int
        ? payload['keyEpoch'] as int
        : 1;

    await saveReplayKey(groupId, keyGeneration);
    final identity = await legacySigningIdentity(
      groupId: groupId,
      senderPeerId: senderPeerId,
      senderDeviceId: legacyString(payload['senderDeviceId']),
      senderTransportPeerId: legacyString(payload['transportPeerId']),
    );
    final payloadType = payload['type'] == groupOfflineReplayPayloadTypeReaction
        ? groupOfflineReplayPayloadTypeReaction
        : groupOfflineReplayPayloadTypeMessage;
    final plaintext = payloadType == groupOfflineReplayPayloadTypeReaction
        ? (legacyString(payload['reaction']) ?? jsonEncode(payload))
        : jsonEncode(payload);
    final messageId =
        legacyString(payload['messageId']) ?? legacyString(payload['id']);
    final replayEnvelope = await buildGroupOfflineReplayEnvelope(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      payloadType: payloadType,
      plaintext: plaintext,
      messageId: messageId,
      senderPeerId: senderPeerId,
      senderPublicKey: identity.publicKey,
      senderPrivateKey: 'sk-$senderPeerId',
      senderDeviceId: identity.deviceId,
      senderTransportPeerId: identity.transportPeerId,
      keyInfo: GroupKeyInfo(
        groupId: groupId,
        keyGeneration: keyGeneration,
        encryptedKey: 'replay-key-$keyGeneration',
        createdAt: DateTime.utc(2026, 5, 2),
      ),
    );
    return {
      'from': relayMessage['from'] ?? identity.transportPeerId ?? senderPeerId,
      'message': replayEnvelope,
      if (relayMessage.containsKey('timestamp'))
        'timestamp': relayMessage['timestamp'],
    };
  }

  void configureLegacyReplaySigning(_CursorInboxBridge targetBridge) {
    targetBridge.signLegacyReplayMessage = signedLegacyRelayMessage;
  }

  setUp(() async {
    bridge = _CursorInboxBridge();
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();
    configureLegacyReplaySigning(bridge);

    await groupRepo.saveGroup(testGroup);
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-sender',
        username: 'Sender',
        role: MemberRole.writer,
        publicKey: 'pk-sender',
        joinedAt: DateTime.now().toUtc(),
      ),
    );
  });

  Map<String, dynamic> repairMessage({
    required String id,
    required String text,
    required DateTime timestamp,
    String senderId = 'peer-sender',
  }) {
    return {
      'groupId': 'group-1',
      'senderId': senderId,
      'senderUsername': 'Sender',
      'keyEpoch': 1,
      'text': text,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'messageId': id,
    };
  }

  Future<String> signedReplayEnvelope({
    required String payloadType,
    required String plaintext,
    required String messageId,
    String senderPeerId = 'peer-sender',
    String senderPublicKey = 'pk-sender',
    String senderPrivateKey = 'sk-sender',
    int keyGeneration = 1,
  }) {
    return buildGroupOfflineReplayEnvelope(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      payloadType: payloadType,
      plaintext: plaintext,
      messageId: messageId,
      senderPeerId: senderPeerId,
      senderPublicKey: senderPublicKey,
      senderPrivateKey: senderPrivateKey,
      keyInfo: GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: keyGeneration,
        encryptedKey: 'replay-key-$keyGeneration',
        createdAt: DateTime.utc(2026, 5, 2),
      ),
    );
  }

  Future<void> saveDefaultReplayKey({
    InMemoryGroupRepository? repository,
  }) async {
    await (repository ?? groupRepo).saveKey(
      GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 1,
        encryptedKey: 'replay-key-1',
        createdAt: DateTime.utc(2026, 5, 2),
      ),
    );
  }

  Future<Map<String, dynamic>> signedRelayMessage({
    required String id,
    required String text,
    DateTime? timestamp,
    String senderId = 'peer-sender',
    String senderPublicKey = 'pk-sender',
    String senderPrivateKey = 'sk-sender',
    String senderUsername = 'Sender',
    List<Map<String, dynamic>>? receipts,
  }) async {
    final payload = repairMessage(
      id: id,
      text: text,
      timestamp: timestamp ?? DateTime.utc(2026, 5, 1, 12),
      senderId: senderId,
    )..['senderUsername'] = senderUsername;
    if (receipts != null) {
      payload['receipts'] = receipts;
    }
    return {
      'from': senderId,
      'message': await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: jsonEncode(payload),
        messageId: id,
        senderPeerId: senderId,
        senderPublicKey: senderPublicKey,
        senderPrivateKey: senderPrivateKey,
      ),
    };
  }

  Map<String, dynamic> historyGap({
    required String expectedRangeHash,
    List<String> candidateSources = const ['peer-good'],
    String gapId = 'gap-1',
  }) {
    return {
      'groupId': 'group-1',
      'gapId': gapId,
      'missingAfterMessageId': 'msg-before',
      'missingBeforeMessageId': 'msg-after',
      'expectedRangeHash': expectedRangeHash,
      'expectedHeadMessageId': 'msg-after',
      'candidateSourcePeerIds': candidateSources,
    };
  }

  test(
    'EK004 rejects invalid signed replay for all offline event families before side effects',
    () async {
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'replay-key-1',
          createdAt: DateTime.utc(2026, 5, 2),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-target',
          username: 'Target',
          role: MemberRole.writer,
          publicKey: 'pk-target',
          joinedAt: DateTime.utc(2026, 5, 2),
        ),
      );
      final reactionRepo = FakeReactionRepository();
      final families =
          <({String family, String payloadType, String plaintext})>[
            (
              family: 'group_message',
              payloadType: groupOfflineReplayPayloadTypeMessage,
              plaintext: jsonEncode({
                'groupId': 'group-1',
                'senderId': 'peer-sender',
                'keyEpoch': 1,
                'text': 'message',
                'timestamp': '2026-05-02T07:15:00.000Z',
                'messageId': 'ek004-group-message',
              }),
            ),
            (
              family: 'group_reaction',
              payloadType: groupOfflineReplayPayloadTypeReaction,
              plaintext: jsonEncode({
                'id': 'ek004-group-reaction',
                'messageId': 'ek004-group-message',
                'emoji': '👍',
                'action': 'add',
                'senderPeerId': 'peer-sender',
                'timestamp': '2026-05-02T07:15:01.000Z',
              }),
            ),
            for (final family in <String>[
              'member_added',
              'members_added',
              'member_removed',
              'member_banned',
              'member_unbanned',
              'member_role_updated',
              'group_message_deleted',
              'group_metadata_updated',
              'group_dissolved',
              'key_rotated',
              'member_joined',
            ])
              (
                family: family,
                payloadType: groupOfflineReplayPayloadTypeMessage,
                plaintext: jsonEncode({
                  'groupId': 'group-1',
                  'senderId': 'peer-sender',
                  'keyEpoch': 1,
                  'text': jsonEncode({
                    '__sys': family,
                    'targetPeerId': 'peer-target',
                    'targetMessageId': 'ek004-target-message',
                    'member': {'peerId': 'peer-target', 'username': 'Target'},
                    'newKeyEpoch': 2,
                    'changedAt': '2026-05-02T07:15:02.000Z',
                  }),
                  'timestamp': '2026-05-02T07:15:02.000Z',
                  'messageId': 'ek004-$family',
                }),
              ),
          ];

      final relayMessages = <Map<String, dynamic>>[];
      for (final entry in families) {
        final replayEnvelope = await signedReplayEnvelope(
          payloadType: entry.payloadType,
          plaintext: entry.plaintext,
          messageId: 'ek004-${entry.family}',
        );
        relayMessages.add({
          'from': 'peer-sender',
          'message': replayEnvelope,
          'timestamp': relayMessages.length + 1,
        });
      }
      bridge.addPage('group-1', '', relayMessages, '');
      bridge.responses['payload.verify'] = {'ok': true, 'valid': false};
      bridge.commandLog.clear();

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
      );

      expect(bridge.commandLog, isNot(contains('group.decrypt')));
      expect(msgRepo.count, 0);
      expect(
        await reactionRepo.getReactionsForMessage('ek004-group-message'),
        isEmpty,
      );
      expect(await groupRepo.getGroup('group-1'), isNotNull);
      expect(await groupRepo.getMember('group-1', 'peer-target'), isNotNull);
    },
  );

  test(
    'EK004 invalid or missing replay signatures abort before cursor side effects',
    () async {
      Future<void> runCase({
        required String caseName,
        required void Function(Map<String, dynamic> replayEnvelope) mutate,
        bool forceInvalidSignature = false,
      }) async {
        final localBridge = _CursorInboxBridge();
        final localGroupRepo = InMemoryGroupRepository();
        final localMsgRepo = InMemoryGroupMessageRepository();
        await localGroupRepo.saveGroup(testGroup);
        await localGroupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-sender',
            username: 'Sender',
            role: MemberRole.writer,
            publicKey: 'pk-sender',
            joinedAt: DateTime.utc(2026, 5, 2),
          ),
        );
        await saveDefaultReplayKey(repository: localGroupRepo);
        final replayEnvelope =
            jsonDecode(
                  await buildGroupOfflineReplayEnvelope(
                    bridge: localBridge,
                    groupRepo: localGroupRepo,
                    groupId: 'group-1',
                    payloadType: groupOfflineReplayPayloadTypeMessage,
                    plaintext: jsonEncode({
                      'groupId': 'group-1',
                      'senderId': 'peer-sender',
                      'keyEpoch': 1,
                      'text': 'must not commit cursor',
                      'timestamp': '2026-05-02T07:53:00.000Z',
                      'messageId': 'ek004-cursor-$caseName',
                      'receipts': [
                        {
                          'messageId': 'ek004-cursor-$caseName',
                          'receiptType': groupMessageReceiptTypeRead,
                          'memberPeerId': 'peer-local',
                          'receiptAt': '2026-05-02T07:53:01.000Z',
                        },
                      ],
                    }),
                    messageId: 'ek004-cursor-$caseName',
                    senderPeerId: 'peer-sender',
                    senderPublicKey: 'pk-sender',
                    senderPrivateKey: 'sk-sender',
                    keyInfo: GroupKeyInfo(
                      groupId: 'group-1',
                      keyGeneration: 1,
                      encryptedKey: 'replay-key-1',
                      createdAt: DateTime.utc(2026, 5, 2),
                    ),
                  ),
                )
                as Map<String, dynamic>;
        mutate(replayEnvelope);
        localBridge.addPage('group-1', '', [
          {
            'from': 'peer-sender',
            'message': jsonEncode(replayEnvelope),
            'timestamp': 1,
          },
        ], 'cursor-after-$caseName');
        if (forceInvalidSignature) {
          localBridge.responses['payload.verify'] = {
            'ok': true,
            'valid': false,
          };
        }

        await drainGroupOfflineInbox(
          bridge: localBridge,
          groupRepo: localGroupRepo,
          msgRepo: localMsgRepo,
          selfPeerId: 'peer-local',
        );

        expect(await localMsgRepo.getMessage('ek004-cursor-$caseName'), isNull);
        expect(await localMsgRepo.getInboxCursor('group-1'), isNull);
        expect(
          await localMsgRepo.getReceiptsForMessage(
            'group-1',
            'ek004-cursor-$caseName',
          ),
          isEmpty,
        );
        expect(localBridge.commandLog, isNot(contains('group.decrypt')));
      }

      await runCase(
        caseName: 'invalid',
        mutate: (_) {},
        forceInvalidSignature: true,
      );
      await runCase(
        caseName: 'missing',
        mutate: (replayEnvelope) => replayEnvelope.remove('signature'),
      );
    },
  );

  test(
    'GE-018 seeded offline replay envelope tampering rejects before plaintext render',
    () async {
      Future<void> seedGroupState(InMemoryGroupRepository repository) async {
        await repository.saveGroup(testGroup);
        await repository.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-sender',
            username: 'Sender',
            role: MemberRole.writer,
            publicKey: 'pk-sender',
            joinedAt: DateTime.utc(2026, 5, 2),
          ),
        );
        await saveDefaultReplayKey(repository: repository);
      }

      Future<Map<String, dynamic>> buildReplayMap({
        required _CursorInboxBridge bridge,
        required InMemoryGroupRepository repository,
        required String messageId,
        required String plaintextMarker,
      }) async {
        final replay = await buildGroupOfflineReplayEnvelope(
          bridge: bridge,
          groupRepo: repository,
          groupId: 'group-1',
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintext: jsonEncode({
            'groupId': 'group-1',
            'senderId': 'peer-sender',
            'keyEpoch': 1,
            'text': plaintextMarker,
            'timestamp': '2026-05-13T18:40:00.000Z',
            'messageId': messageId,
            'receipts': [
              {
                'messageId': messageId,
                'receiptType': groupMessageReceiptTypeRead,
                'memberPeerId': 'peer-local',
                'receiptAt': '2026-05-13T18:40:01.000Z',
              },
            ],
          }),
          messageId: messageId,
          senderPeerId: 'peer-sender',
          senderPublicKey: 'pk-sender',
          senderPrivateKey: 'sk-sender',
          recipientPeerIds: const ['peer-local'],
          keyInfo: GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 1,
            encryptedKey: 'replay-key-1',
            createdAt: DateTime.utc(2026, 5, 2),
          ),
        );
        return Map<String, dynamic>.from(jsonDecode(replay) as Map);
      }

      Future<void> runValidControl() async {
        final localBridge = _CursorInboxBridge();
        final localGroupRepo = InMemoryGroupRepository();
        final localMsgRepo = InMemoryGroupMessageRepository();
        await seedGroupState(localGroupRepo);
        final replayEnvelope = await buildReplayMap(
          bridge: localBridge,
          repository: localGroupRepo,
          messageId: 'ge018-valid-control',
          plaintextMarker: 'GE-018 valid replay control',
        );
        localBridge.addPage('group-1', '', [
          {
            'from': 'peer-sender',
            'message': jsonEncode(replayEnvelope),
            'timestamp': 1,
          },
        ], '');

        await drainGroupOfflineInbox(
          bridge: localBridge,
          groupRepo: localGroupRepo,
          msgRepo: localMsgRepo,
          selfPeerId: 'peer-local',
        );

        final saved = await localMsgRepo.getMessage('ge018-valid-control');
        expect(saved, isNotNull);
        expect(saved!.text, 'GE-018 valid replay control');
        expect(localBridge.commandLog, contains('group.decrypt'));
        expect(
          await localMsgRepo.getReceiptsForMessage(
            'group-1',
            'ge018-valid-control',
            receiptType: groupMessageReceiptTypeRead,
          ),
          hasLength(1),
        );
      }

      Future<void> runTamperCase({
        required String caseName,
        required void Function(Map<String, dynamic> replayEnvelope) mutate,
        bool forceInvalidSignature = false,
        bool malformedRelayJson = false,
      }) async {
        final localBridge = _CursorInboxBridge();
        final localGroupRepo = InMemoryGroupRepository();
        final localMsgRepo = InMemoryGroupMessageRepository();
        await seedGroupState(localGroupRepo);
        final messageId = 'ge018-$caseName';
        final replayEnvelope = await buildReplayMap(
          bridge: localBridge,
          repository: localGroupRepo,
          messageId: messageId,
          plaintextMarker: 'GE-018 tampered replay plaintext $caseName',
        );
        mutate(replayEnvelope);
        localBridge.addPage('group-1', '', [
          {
            'from': 'peer-sender',
            'message': malformedRelayJson
                ? '{"kind":"group_offline_replay",'
                : jsonEncode(replayEnvelope),
            'timestamp': 1,
          },
        ], 'cursor-after-$caseName');
        if (forceInvalidSignature) {
          localBridge.responses['payload.verify'] = {
            'ok': true,
            'valid': false,
          };
        }

        await drainGroupOfflineInbox(
          bridge: localBridge,
          groupRepo: localGroupRepo,
          msgRepo: localMsgRepo,
          selfPeerId: 'peer-local',
        );

        expect(await localMsgRepo.getMessage(messageId), isNull);
        expect(localMsgRepo.count, 0);
        expect(await localMsgRepo.getInboxCursor('group-1'), isNull);
        expect(
          await localMsgRepo.getReceiptsForMessage(
            'group-1',
            messageId,
            receiptType: groupMessageReceiptTypeRead,
          ),
          isEmpty,
        );
        expect(localBridge.commandLog, isNot(contains('group.decrypt')));
      }

      await runValidControl();

      final mutations =
          <
            ({
              String caseName,
              void Function(Map<String, dynamic>) mutate,
              bool forceInvalidSignature,
              bool malformedRelayJson,
            })
          >[
            (
              caseName: 'group-id',
              mutate: (envelope) => envelope['groupId'] = 'group-other',
              forceInvalidSignature: false,
              malformedRelayJson: false,
            ),
            (
              caseName: 'payload-type',
              mutate: (envelope) => envelope['payloadType'] =
                  groupOfflineReplayPayloadTypeReaction,
              forceInvalidSignature: false,
              malformedRelayJson: false,
            ),
            (
              caseName: 'message-id',
              mutate: (envelope) => envelope['messageId'] = 'ge018-other-id',
              forceInvalidSignature: false,
              malformedRelayJson: false,
            ),
            (
              caseName: 'sender-peer',
              mutate: (envelope) => envelope['senderPeerId'] = 'peer-other',
              forceInvalidSignature: false,
              malformedRelayJson: false,
            ),
            (
              caseName: 'sender-device',
              mutate: (envelope) =>
                  envelope['senderDeviceId'] = 'peer-other-device',
              forceInvalidSignature: false,
              malformedRelayJson: false,
            ),
            (
              caseName: 'sender-transport',
              mutate: (envelope) =>
                  envelope['senderTransportPeerId'] = 'peer-other-transport',
              forceInvalidSignature: false,
              malformedRelayJson: false,
            ),
            (
              caseName: 'sender-public-key',
              mutate: (envelope) => envelope['senderPublicKey'] = 'pk-other',
              forceInvalidSignature: false,
              malformedRelayJson: false,
            ),
            (
              caseName: 'recipient-hash',
              mutate: (envelope) => envelope['recipientSetHash'] = 'bad-hash',
              forceInvalidSignature: false,
              malformedRelayJson: false,
            ),
            (
              caseName: 'ciphertext',
              mutate: (envelope) => envelope['ciphertext'] = jsonEncode({
                'groupId': 'group-1',
                'senderId': 'peer-sender',
                'keyEpoch': 1,
                'text': 'GE-018 unsigned ciphertext substitution',
                'timestamp': '2026-05-13T18:41:00.000Z',
                'messageId': 'ge018-ciphertext',
              }),
              forceInvalidSignature: false,
              malformedRelayJson: false,
            ),
            (
              caseName: 'nonce',
              mutate: (envelope) => envelope['nonce'] = 'ge018-bad-nonce',
              forceInvalidSignature: false,
              malformedRelayJson: false,
            ),
            (
              caseName: 'signature-algorithm',
              mutate: (envelope) =>
                  envelope['signatureAlgorithm'] = 'ed25519-v0',
              forceInvalidSignature: false,
              malformedRelayJson: false,
            ),
            (
              caseName: 'signed-payload',
              mutate: (envelope) => envelope['signedPayload'] = '{}',
              forceInvalidSignature: false,
              malformedRelayJson: false,
            ),
            (
              caseName: 'signature',
              mutate: (envelope) =>
                  envelope['signature'] = 'ge018-bad-signature',
              forceInvalidSignature: true,
              malformedRelayJson: false,
            ),
            (
              caseName: 'key-epoch',
              mutate: (envelope) => envelope['keyEpoch'] = 2,
              forceInvalidSignature: false,
              malformedRelayJson: false,
            ),
            (
              caseName: 'missing-ciphertext',
              mutate: (envelope) => envelope.remove('ciphertext'),
              forceInvalidSignature: false,
              malformedRelayJson: false,
            ),
            (
              caseName: 'missing-nonce',
              mutate: (envelope) => envelope.remove('nonce'),
              forceInvalidSignature: false,
              malformedRelayJson: false,
            ),
            (
              caseName: 'malformed-json',
              mutate: (_) {},
              forceInvalidSignature: false,
              malformedRelayJson: true,
            ),
          ];

      final ordered = [...mutations]..shuffle(Random(18018));
      for (final mutation in ordered) {
        await runTamperCase(
          caseName: mutation.caseName,
          mutate: mutation.mutate,
          forceInvalidSignature: mutation.forceInvalidSignature,
          malformedRelayJson: mutation.malformedRelayJson,
        );
      }
    },
  );

  test(
    'EK004 unsigned non envelope replay forms fail closed before mutation',
    () async {
      Future<void> runUnsignedCase({
        required String caseName,
        required Map<String, dynamic> relayMessage,
      }) async {
        final localBridge = _CursorInboxBridge();
        final localGroupRepo = InMemoryGroupRepository();
        final localMsgRepo = InMemoryGroupMessageRepository();
        await localGroupRepo.saveGroup(testGroup);
        await localGroupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-sender',
            username: 'Sender',
            role: MemberRole.writer,
            publicKey: 'pk-sender',
            joinedAt: DateTime.utc(2026, 5, 2),
          ),
        );
        localBridge.addPage('group-1', '', [relayMessage], 'cursor-$caseName');

        await drainGroupOfflineInbox(
          bridge: localBridge,
          groupRepo: localGroupRepo,
          msgRepo: localMsgRepo,
          selfPeerId: 'peer-local',
        );

        expect(
          await localMsgRepo.getMessage('ek004-unsigned-$caseName'),
          isNull,
        );
        expect(localMsgRepo.count, 0);
        expect(await localMsgRepo.getInboxCursor('group-1'), isNull);
      }

      await runUnsignedCase(
        caseName: 'decoded',
        relayMessage: {
          'from': 'peer-sender',
          'message': jsonEncode({
            'groupId': 'group-1',
            'senderId': 'peer-sender',
            'senderUsername': 'Sender',
            'keyEpoch': 1,
            'text': 'decoded unsigned relay replay',
            'timestamp': '2026-05-02T07:53:00.000Z',
            'messageId': 'ek004-unsigned-decoded',
          }),
        },
      );
      await runUnsignedCase(
        caseName: 'sender-map',
        relayMessage: {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'already decoded unsigned replay',
          'timestamp': '2026-05-02T07:53:00.000Z',
          'messageId': 'ek004-unsigned-sender-map',
        },
      );
      await runUnsignedCase(
        caseName: 'fallback',
        relayMessage: {
          'from': 'peer-sender',
          'message': 'fallback unsigned relay replay',
        },
      );
    },
  );

  test(
    'EK004 history repair rejects invalid replay signature without marking repaired',
    () async {
      await saveDefaultReplayKey();
      final replayEnvelope = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: jsonEncode({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'keyEpoch': 1,
          'text': 'history repaired',
          'timestamp': '2026-05-02T07:16:00.000Z',
          'messageId': 'ek004-history-repair',
        }),
        messageId: 'ek004-history-repair',
      );
      final repairRelayMessage = {
        'from': 'peer-sender',
        'message': replayEnvelope,
        'timestamp': 1,
      };
      final rangeHash = computeGroupHistoryRangeHash([repairRelayMessage]);
      bridge.addPage(
        'group-1',
        '',
        const <Map<String, dynamic>>[],
        '',
        historyGaps: [
          historyGap(
            expectedRangeHash: rangeHash,
            candidateSources: const ['peer-sender'],
          ),
        ],
      );
      bridge.addRepairResponse(
        groupId: 'group-1',
        gapId: 'gap-1',
        sourcePeerId: 'peer-sender',
        response: {
          'ok': true,
          'groupId': 'group-1',
          'gapId': 'gap-1',
          'sourcePeerId': 'peer-sender',
          'rangeHash': rangeHash,
          'headMessageId': 'msg-after',
          'messages': [repairRelayMessage],
        },
      );
      bridge.responses['payload.verify'] = {'ok': true, 'valid': false};
      bridge.commandLog.clear();
      final historyRepo = _InMemoryGroupHistoryGapRepairRepository();

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        historyGapRepairRepo: historyRepo,
      );

      expect(bridge.commandLog, isNot(contains('group.decrypt')));
      expect(await msgRepo.getMessage('ek004-history-repair'), isNull);
      final repair = await historyRepo.getRepair(
        groupId: 'group-1',
        gapId: 'gap-1',
      );
      expect(repair, isNotNull);
      expect(repair!.status, groupHistoryGapRepairStatusFailed);
      expect(repair.failureReason, 'application_rejected_message');
      expect(repair.repairedMessageIds, isEmpty);
    },
  );

  test(
    'PREREQ-GROUP-SYNC-RECEIPTS loads durable cursor and advances only after page apply',
    () async {
      await saveDefaultReplayKey();
      await msgRepo.runInboxPageTransaction(
        groupId: 'group-1',
        nextCursor: 'cursor-2',
        apply: (_) async {},
      );
      bridge.addPage('group-1', 'cursor-2', [
        await signedRelayMessage(
          id: 'sync-cursor-msg',
          text: 'after persisted cursor',
          timestamp: DateTime.utc(2026, 5, 1, 12),
        ),
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        selfPeerId: 'peer-local',
        retentionNowUtc: _fixedDateFixtureRetentionNow,
      );

      final cursorCmd = bridge.sentMessages
          .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
          .firstWhere((cmd) => cmd['cmd'] == 'group:inboxRetrieveCursor');
      expect(cursorCmd['payload']['cursor'], 'cursor-2');
      expect(await msgRepo.getMessage('sync-cursor-msg'), isNotNull);
      expect(await msgRepo.getInboxCursor('group-1'), '');
      expect(
        await msgRepo.getReceiptsForMessage('group-1', 'sync-cursor-msg'),
        hasLength(1),
      );
    },
  );

  test(
    'PREREQ-GROUP-SYNC-RECEIPTS failed page commit does not advance cursor or save receipts',
    () async {
      // After the lock-window refactor (drain Phase 1 = process messages
      // outside any DB write transaction; Phase 2 = small atomic
      // cursor+receipts commit), a failure in the Phase 2 transaction must
      // still leave the cursor un-advanced and receipts un-committed so the
      // re-drain retries this page. The persisted message itself may already
      // exist from Phase 1 — handleIncomingGroupMessage is idempotent on
      // messageId and the next drain dedupes it instead of duplicating.
      await saveDefaultReplayKey();
      bridge.addPage('group-1', '', [
        await signedRelayMessage(
          id: 'sync-rollback-msg',
          text: 'rolled back',
          timestamp: DateTime.utc(2026, 5, 1, 12),
        ),
      ], 'cursor-after-failure');
      msgRepo.failInboxPageTransaction = true;

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        selfPeerId: 'peer-local',
        retentionNowUtc: _fixedDateFixtureRetentionNow,
      );

      expect(await msgRepo.getInboxCursor('group-1'), isNull);
      expect(
        await msgRepo.getReceiptsForMessage('group-1', 'sync-rollback-msg'),
        isEmpty,
      );
    },
  );

  test(
    'PREREQ-GROUP-SYNC-RECEIPTS listener replay failure does not commit cursor or receipts',
    () async {
      await saveDefaultReplayKey();
      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        appendGroupEventLogEntry:
            ({
              required groupId,
              required eventType,
              required sourcePeerId,
              required sourceEventId,
              required sourceTimestamp,
              required payload,
              createdAt,
            }) async {
              throw StateError('forced listener replay failure');
            },
      );
      addTearDown(listener.dispose);

      bridge.addPage('group-1', '', [
        await signedRelayMessage(
          id: 'sync-listener-failure-msg',
          text: 'listener failure',
          timestamp: DateTime.utc(2026, 5, 1, 12),
          receipts: [
            {
              'messageId': 'sync-listener-failure-msg',
              'receiptType': groupMessageReceiptTypeRead,
              'memberPeerId': 'peer-local',
              'receiptAt': '2026-05-01T12:02:00.000Z',
            },
          ],
        ),
      ], 'cursor-after-listener-failure');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
        selfPeerId: 'peer-local',
        retentionNowUtc: _fixedDateFixtureRetentionNow,
      );

      expect(await msgRepo.getMessage('sync-listener-failure-msg'), isNull);
      expect(await msgRepo.getInboxCursor('group-1'), isNull);
      expect(
        await msgRepo.getReceiptsForMessage(
          'group-1',
          'sync-listener-failure-msg',
        ),
        isEmpty,
      );
    },
  );

  test(
    'PREREQ-GROUP-SYNC-RECEIPTS system replay failure does not emit timeline or commit cursor',
    () async {
      await saveDefaultReplayKey();
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-new',
          username: 'New Member',
          role: MemberRole.writer,
          publicKey: 'pk-peer-new',
          joinedAt: DateTime.utc(2026, 5, 1, 11),
        ),
      );
      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
      );
      final emitted = <GroupMessage>[];
      final subscription = listener.groupMessageStream.listen(emitted.add);
      addTearDown(() async {
        await subscription.cancel();
        listener.dispose();
      });

      final eventAt = DateTime.utc(2026, 5, 1, 12);
      final timelineMessageId =
          'sys-member_joined:group-1:peer-new:${eventAt.microsecondsSinceEpoch}';
      msgRepo.failSaveMessageIds.add(timelineMessageId);
      bridge.addPage('group-1', '', [
        await signedRelayMessage(
          id: 'system-replay-failure-msg',
          senderId: 'peer-new',
          senderPublicKey: 'pk-peer-new',
          senderPrivateKey: 'sk-peer-new',
          senderUsername: 'New Member',
          text: jsonEncode({
            '__sys': 'member_joined',
            'member': {'peerId': 'peer-new', 'username': 'New Member'},
          }),
          timestamp: eventAt,
        ),
      ], 'cursor-after-system-failure');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
        retentionNowUtc: _fixedDateFixtureRetentionNow,
      );

      await Future<void>.delayed(Duration.zero);
      expect(await msgRepo.getMessage(timelineMessageId), isNull);
      expect(await msgRepo.getInboxCursor('group-1'), isNull);
      expect(emitted, isEmpty);
    },
  );

  test(
    'PREREQ-GROUP-SYNC-RECEIPTS duplicate receipt replay is idempotent',
    () async {
      await saveDefaultReplayKey();
      bridge.addPage('group-1', '', [
        await signedRelayMessage(
          id: 'sync-receipt-msg',
          text: 'read me',
          timestamp: DateTime.utc(2026, 5, 1, 12),
          receipts: [
            {
              'messageId': 'sync-receipt-msg',
              'receiptType': groupMessageReceiptTypeRead,
              'memberPeerId': 'peer-local',
              'receiptAt': '2026-05-01T12:02:00.000Z',
            },
          ],
        ),
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        selfPeerId: 'peer-local',
        retentionNowUtc: _fixedDateFixtureRetentionNow,
      );
      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        selfPeerId: 'peer-local',
        retentionNowUtc: _fixedDateFixtureRetentionNow,
      );

      final receipts = await msgRepo.getReceiptsForMessage(
        'group-1',
        'sync-receipt-msg',
        receiptType: groupMessageReceiptTypeRead,
      );
      expect(receipts, hasLength(1));
      expect((await msgRepo.getMessage('sync-receipt-msg'))!.readAt, isNotNull);
    },
  );

  test(
    'PREREQ-HISTORY-GAP-REPAIR detects a history gap and repairs it from the first authorized matching source',
    () async {
      await saveDefaultReplayKey();
      final historyRepo = _InMemoryGroupHistoryGapRepairRepository();
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-good',
          username: 'Good Source',
          role: MemberRole.reader,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final repairedMessages = [
        await signedRelayMessage(
          id: 'msg-gap-repaired-1',
          text: 'Recovered one',
          timestamp: DateTime.utc(2026, 5, 1, 12, 1),
        ),
        await signedRelayMessage(
          id: 'msg-gap-repaired-2',
          text: 'Recovered two',
          timestamp: DateTime.utc(2026, 5, 1, 12, 2),
        ),
      ];
      final rangeHash = computeGroupHistoryRangeHash(repairedMessages);

      bridge.addPage(
        'group-1',
        '',
        [],
        '',
        historyGaps: [historyGap(expectedRangeHash: rangeHash)],
      );
      bridge.addRepairResponse(
        groupId: 'group-1',
        gapId: 'gap-1',
        sourcePeerId: 'peer-good',
        response: {
          'ok': true,
          'groupId': 'group-1',
          'gapId': 'gap-1',
          'sourcePeerId': 'peer-good',
          'rangeHash': rangeHash,
          'headMessageId': 'msg-after',
          'messages': repairedMessages,
        },
      );

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        historyGapRepairRepo: historyRepo,
      );

      expect(await msgRepo.getMessage('msg-gap-repaired-1'), isNotNull);
      expect(await msgRepo.getMessage('msg-gap-repaired-2'), isNotNull);
      final repair = await historyRepo.getRepair(
        groupId: 'group-1',
        gapId: 'gap-1',
      );
      expect(repair!.status, groupHistoryGapRepairStatusRepaired);
      expect(repair.repairedMessageIds, [
        'msg-gap-repaired-1',
        'msg-gap-repaired-2',
      ]);
      expect(bridge.commandLog, contains('group:historyRepairRange'));
    },
  );

  test(
    'GI-026 history gap metadata is preserved to app repair layer',
    () async {
      await saveDefaultReplayKey();
      final historyRepo = _InMemoryGroupHistoryGapRepairRepository();
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-good',
          username: 'Good Source',
          role: MemberRole.reader,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final repairedMessages = [
        await signedRelayMessage(
          id: 'gi026-repaired-head',
          text: 'Recovered GI-026',
          timestamp: DateTime.utc(2026, 5, 1, 12, 26),
        ),
      ];
      final expectedRangeHash = computeGroupHistoryRangeHash(repairedMessages);
      const expectedSources = ['peer-good', 'peer-sender'];
      final gap = {
        'groupId': 'group-1',
        'gapId': 'gap-gi026-preserve',
        'missingAfterMessageId': 'gi026-before',
        'missingBeforeMessageId': 'gi026-after',
        'expectedRangeHash': expectedRangeHash,
        'expectedHeadMessageId': 'gi026-repaired-head',
        'candidateSourcePeerIds': expectedSources,
      };
      bridge.addPage(
        'group-1',
        '',
        const <Map<String, dynamic>>[],
        '',
        historyGaps: [gap],
      );

      final capturedGaps = <GroupInboxHistoryGap>[];
      final capturedSources = <String>[];
      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        historyGapRepairRepo: historyRepo,
        requestHistoryRepairRange:
            ({required gap, required sourcePeerId, int limit = 50}) async {
              capturedGaps.add(gap);
              capturedSources.add(sourcePeerId);
              expect(limit, 50);
              return GroupHistoryRepairRangeResult(
                groupId: gap.groupId,
                gapId: gap.gapId,
                sourcePeerId: sourcePeerId,
                rangeHash: gap.expectedRangeHash,
                headMessageId: gap.expectedHeadMessageId,
                messages: repairedMessages,
              );
            },
      );

      expect(capturedSources, ['peer-good']);
      expect(capturedGaps, hasLength(1));
      final captured = capturedGaps.single;
      expect(captured.groupId, 'group-1');
      expect(captured.gapId, 'gap-gi026-preserve');
      expect(captured.missingAfterMessageId, 'gi026-before');
      expect(captured.missingBeforeMessageId, 'gi026-after');
      expect(captured.expectedRangeHash, expectedRangeHash);
      expect(captured.expectedHeadMessageId, 'gi026-repaired-head');
      expect(captured.candidateSourcePeerIds, expectedSources);

      final repair = await historyRepo.getRepair(
        groupId: 'group-1',
        gapId: 'gap-gi026-preserve',
      );
      expect(repair, isNotNull);
      expect(repair!.missingAfterMessageId, 'gi026-before');
      expect(repair.missingBeforeMessageId, 'gi026-after');
      expect(repair.expectedRangeHash, expectedRangeHash);
      expect(repair.expectedHeadMessageId, 'gi026-repaired-head');
      expect(repair.candidateSourcePeerIds, expectedSources);
      expect(repair.attemptedSourcePeerIds, ['peer-good']);
      expect(repair.status, groupHistoryGapRepairStatusRepaired);
      expect(repair.repairedMessageIds, ['gi026-repaired-head']);
      expect(await msgRepo.getMessage('gi026-repaired-head'), isNotNull);
    },
  );

  test(
    'GI-031 repair range hash mismatch is rejected without rendering',
    () async {
      await saveDefaultReplayKey();
      final historyRepo = _InMemoryGroupHistoryGapRepairRepository();
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-good',
          username: 'Good Source',
          role: MemberRole.reader,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final expectedMessages = [
        await signedRelayMessage(
          id: 'gi031-expected-head',
          text: 'Expected repair payload',
          timestamp: DateTime.utc(2026, 5, 1, 12, 30),
        ),
      ];
      final expectedRangeHash = computeGroupHistoryRangeHash(expectedMessages);
      final mismatchedMessages = [
        await signedRelayMessage(
          id: 'gi031-rejected',
          text: 'Untrusted repair payload',
          timestamp: DateTime.utc(2026, 5, 1, 12, 31),
        ),
      ];
      final mismatchedRangeHash = computeGroupHistoryRangeHash(
        mismatchedMessages,
      );
      expect(mismatchedRangeHash, isNot(expectedRangeHash));

      bridge.addPage(
        'group-1',
        '',
        const <Map<String, dynamic>>[],
        '',
        historyGaps: [
          historyGap(expectedRangeHash: expectedRangeHash, gapId: 'gap-gi031'),
        ],
      );
      bridge.addRepairResponse(
        groupId: 'group-1',
        gapId: 'gap-gi031',
        sourcePeerId: 'peer-good',
        response: {
          'ok': true,
          'groupId': 'group-1',
          'gapId': 'gap-gi031',
          'sourcePeerId': 'peer-good',
          'rangeHash': mismatchedRangeHash,
          'headMessageId': 'msg-after',
          'messages': mismatchedMessages,
        },
      );

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        historyGapRepairRepo: historyRepo,
      );

      expect(await msgRepo.getMessage('gi031-rejected'), isNull);
      final repair = await historyRepo.getRepair(
        groupId: 'group-1',
        gapId: 'gap-gi031',
      );
      expect(repair, isNotNull);
      expect(repair!.status, groupHistoryGapRepairStatusFailed);
      expect(repair.failureReason, 'range_hash_mismatch');
      expect(repair.repairedMessageIds, isEmpty);
      expect(repair.attemptedSourcePeerIds, ['peer-good']);
    },
  );

  test('GI-032 repair head mismatch is rejected without rendering', () async {
    await saveDefaultReplayKey();
    final historyRepo = _InMemoryGroupHistoryGapRepairRepository();
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-good',
        username: 'Good Source',
        role: MemberRole.reader,
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    final repairedMessages = [
      await signedRelayMessage(
        id: 'gi032-rejected',
        text: 'Wrong head repair payload',
        timestamp: DateTime.utc(2026, 5, 1, 12, 32),
      ),
    ];
    final expectedRangeHash = computeGroupHistoryRangeHash(repairedMessages);

    bridge.addPage(
      'group-1',
      '',
      const <Map<String, dynamic>>[],
      '',
      historyGaps: [
        historyGap(expectedRangeHash: expectedRangeHash, gapId: 'gap-gi032'),
      ],
    );
    bridge.addRepairResponse(
      groupId: 'group-1',
      gapId: 'gap-gi032',
      sourcePeerId: 'peer-good',
      response: {
        'ok': true,
        'groupId': 'group-1',
        'gapId': 'gap-gi032',
        'sourcePeerId': 'peer-good',
        'rangeHash': expectedRangeHash,
        'headMessageId': 'wrong-head',
        'messages': repairedMessages,
      },
    );

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      historyGapRepairRepo: historyRepo,
    );

    expect(await msgRepo.getMessage('gi032-rejected'), isNull);
    final repair = await historyRepo.getRepair(
      groupId: 'group-1',
      gapId: 'gap-gi032',
    );
    expect(repair, isNotNull);
    expect(repair!.status, groupHistoryGapRepairStatusFailed);
    expect(repair.failureReason, 'head_mismatch');
    expect(repair.repairedMessageIds, isEmpty);
    expect(repair.attemptedSourcePeerIds, ['peer-good']);
  });

  test('GI-033 repair source must be a current authorized member', () async {
    await saveDefaultReplayKey();
    final historyRepo = _InMemoryGroupHistoryGapRepairRepository();
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-removed',
        username: 'Removed Source',
        role: MemberRole.reader,
        joinedAt: DateTime.now().toUtc(),
      ),
    );
    await groupRepo.removeMember('group-1', 'peer-removed');
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-good',
        username: 'Good Source',
        role: MemberRole.reader,
        joinedAt: DateTime.now().toUtc(),
      ),
    );
    expect(await groupRepo.getMember('group-1', 'peer-removed'), isNull);

    final repairedMessages = [
      await signedRelayMessage(
        id: 'gi033-repaired',
        text: 'Authorized source repair',
        timestamp: DateTime.utc(2026, 5, 1, 12, 33),
      ),
    ];
    final expectedRangeHash = computeGroupHistoryRangeHash(repairedMessages);

    bridge.addPage(
      'group-1',
      '',
      const <Map<String, dynamic>>[],
      '',
      historyGaps: [
        historyGap(
          expectedRangeHash: expectedRangeHash,
          gapId: 'gap-gi033',
          candidateSources: ['peer-removed', 'peer-rogue', 'peer-good'],
        ),
      ],
    );

    final requestedSources = <String>[];
    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      historyGapRepairRepo: historyRepo,
      requestHistoryRepairRange:
          ({required gap, required sourcePeerId, int limit = 50}) async {
            requestedSources.add(sourcePeerId);
            expect(sourcePeerId, 'peer-good');
            expect(limit, 50);
            return GroupHistoryRepairRangeResult(
              groupId: gap.groupId,
              gapId: gap.gapId,
              sourcePeerId: sourcePeerId,
              rangeHash: gap.expectedRangeHash,
              headMessageId: gap.expectedHeadMessageId,
              messages: repairedMessages,
            );
          },
    );

    expect(requestedSources, ['peer-good']);
    expect(await msgRepo.getMessage('gi033-repaired'), isNotNull);
    final repair = await historyRepo.getRepair(
      groupId: 'group-1',
      gapId: 'gap-gi033',
    );
    expect(repair, isNotNull);
    expect(repair!.status, groupHistoryGapRepairStatusRepaired);
    expect(repair.failureReason, isNull);
    expect(repair.attemptedSourcePeerIds, [
      'peer-removed',
      'peer-rogue',
      'peer-good',
    ]);
    expect(repair.repairedMessageIds, ['gi033-repaired']);
  });

  test(
    'PREREQ-HISTORY-GAP-REPAIR rejects unauthorized and hash-mismatched sources then repairs from a later authorized source',
    () async {
      await saveDefaultReplayKey();
      final historyRepo = _InMemoryGroupHistoryGapRepairRepository();
      for (final peerId in ['peer-bad', 'peer-good']) {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: peerId,
            username: peerId,
            role: MemberRole.reader,
            joinedAt: DateTime.now().toUtc(),
          ),
        );
      }

      final goodMessages = [
        await signedRelayMessage(
          id: 'msg-gap-fallback',
          text: 'Recovered from fallback',
          timestamp: DateTime.utc(2026, 5, 1, 12, 3),
        ),
      ];
      final goodHash = computeGroupHistoryRangeHash(goodMessages);
      final badMessages = [
        repairMessage(
          id: 'msg-gap-bad',
          text: 'Bad source body',
          timestamp: DateTime.utc(2026, 5, 1, 12, 3),
        ),
      ];

      bridge.addPage(
        'group-1',
        '',
        [],
        '',
        historyGaps: [
          historyGap(
            expectedRangeHash: goodHash,
            candidateSources: ['peer-rogue', 'peer-bad', 'peer-good'],
          ),
        ],
      );
      bridge.addRepairResponse(
        groupId: 'group-1',
        gapId: 'gap-1',
        sourcePeerId: 'peer-bad',
        response: {
          'ok': true,
          'groupId': 'group-1',
          'gapId': 'gap-1',
          'sourcePeerId': 'peer-bad',
          'rangeHash': computeGroupHistoryRangeHash(badMessages),
          'headMessageId': 'msg-after',
          'messages': badMessages,
        },
      );
      bridge.addRepairResponse(
        groupId: 'group-1',
        gapId: 'gap-1',
        sourcePeerId: 'peer-good',
        response: {
          'ok': true,
          'groupId': 'group-1',
          'gapId': 'gap-1',
          'sourcePeerId': 'peer-good',
          'rangeHash': goodHash,
          'headMessageId': 'msg-after',
          'messages': goodMessages,
        },
      );

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        historyGapRepairRepo: historyRepo,
      );

      expect(await msgRepo.getMessage('msg-gap-bad'), isNull);
      expect(await msgRepo.getMessage('msg-gap-fallback'), isNotNull);
      final repair = await historyRepo.getRepair(
        groupId: 'group-1',
        gapId: 'gap-1',
      );
      expect(repair!.status, groupHistoryGapRepairStatusRepaired);
      expect(
        repair.attemptedSourcePeerIds,
        containsAll(['peer-rogue', 'peer-bad', 'peer-good']),
      );
      expect(repair.failureReason, isNull);
    },
  );

  test(
    'PREREQ-HISTORY-GAP-REPAIR applies repaired envelopes through replay handling without duplicate or out-of-order rows',
    () async {
      await saveDefaultReplayKey();
      final historyRepo = _InMemoryGroupHistoryGapRepairRepository();
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-good',
          username: 'Good Source',
          role: MemberRole.reader,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      await msgRepo.saveMessage(
        GroupMessage(
          id: 'msg-gap-duplicate',
          groupId: 'group-1',
          senderPeerId: 'peer-sender',
          senderUsername: 'Sender',
          text: 'Already present',
          timestamp: DateTime.utc(2026, 5, 1, 12, 1),
          createdAt: DateTime.utc(2026, 5, 1, 12, 1),
          isIncoming: true,
        ),
      );

      final repairedMessages = [
        await signedRelayMessage(
          id: 'msg-gap-newer',
          text: 'Newer repaired',
          timestamp: DateTime.utc(2026, 5, 1, 12, 3),
        ),
        await signedRelayMessage(
          id: 'msg-gap-duplicate',
          text: 'Already present',
          timestamp: DateTime.utc(2026, 5, 1, 12, 1),
        ),
        await signedRelayMessage(
          id: 'msg-gap-older',
          text: 'Older repaired',
          timestamp: DateTime.utc(2026, 5, 1, 12, 2),
        ),
      ];
      final rangeHash = computeGroupHistoryRangeHash(repairedMessages);
      bridge.addPage(
        'group-1',
        '',
        [],
        '',
        historyGaps: [historyGap(expectedRangeHash: rangeHash)],
      );
      bridge.addRepairResponse(
        groupId: 'group-1',
        gapId: 'gap-1',
        sourcePeerId: 'peer-good',
        response: {
          'ok': true,
          'groupId': 'group-1',
          'gapId': 'gap-1',
          'sourcePeerId': 'peer-good',
          'rangeHash': rangeHash,
          'headMessageId': 'msg-after',
          'messages': repairedMessages,
        },
      );

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        historyGapRepairRepo: historyRepo,
      );

      expect(await msgRepo.getMessage('msg-gap-duplicate'), isNotNull);
      expect(await msgRepo.getMessage('msg-gap-older'), isNotNull);
      expect(await msgRepo.getMessage('msg-gap-newer'), isNotNull);
      expect(await msgRepo.getMessageCount('group-1'), 3);

      final timeline = await msgRepo.getMessagesPage('group-1');
      expect(timeline.map((message) => message.id), [
        'msg-gap-duplicate',
        'msg-gap-older',
        'msg-gap-newer',
      ]);
    },
  );

  test('resume drains group inbox for every joined group', () async {
    // Set up two groups.
    final testGroup2 = GroupModel(
      id: 'group-2',
      name: 'Second Group',
      type: GroupType.chat,
      topicName: '/mknoon/group/group-2',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.member,
    );
    await groupRepo.saveGroup(testGroup2);
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-2',
        peerId: 'peer-sender',
        username: 'Sender',
        role: MemberRole.writer,
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    final ts = DateTime.now().toUtc().toIso8601String();

    // Group 1: one message
    bridge.addPage('group-1', '', [
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Msg for group 1',
        'timestamp': ts,
        'messageId': 'msg-g1-1',
      },
    ], '');

    // Group 2: one message
    bridge.addPage('group-2', '', [
      {
        'groupId': 'group-2',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Msg for group 2',
        'timestamp': ts,
        'messageId': 'msg-g2-1',
      },
    ], '');

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );

    expect(msgRepo.count, 2);

    // Both groups should have had inboxRetrieveCursor called
    final retrieveCount = bridge.commandLog
        .where((c) => c == 'group:inboxRetrieveCursor')
        .length;
    expect(retrieveCount, 2);
  });

  test(
    'MS002 stores relay transport peer id for offline inbox messages',
    () async {
      final ts = DateTime.now().toUtc().toIso8601String();
      bridge.addPage('group-1', '', [
        {
          'from': 'peer-sender',
          'message': jsonEncode({
            'groupId': 'group-1',
            'senderId': 'peer-sender',
            'senderUsername': 'Sender',
            'keyEpoch': 1,
            'text': 'Bound inbox message',
            'timestamp': ts,
            'messageId': 'ms002-inbox-bound',
          }),
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      final stored = await msgRepo.getMessage('ms002-inbox-bound');
      expect(stored, isNotNull);
      expect(stored!.senderPeerId, 'peer-sender');
      expect(stored.transportPeerId, 'peer-sender');
    },
  );

  test(
    'accepts offline replay from a valid registered sender device',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-sender',
          username: 'Sender',
          role: MemberRole.writer,
          publicKey: 'sender-member-pk',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'sender-device-1',
              transportPeerId: 'sender-device-1',
              deviceSigningPublicKey: 'sender-device-pk-1',
              mlKemPublicKey: 'sender-device-mlkem-1',
            ),
          ],
          joinedAt: DateTime.utc(2026, 5, 1, 12),
        ),
      );
      final ts = DateTime.now().toUtc().toIso8601String();
      bridge.addPage('group-1', '', [
        {
          'from': 'sender-device-1',
          'message': jsonEncode({
            'groupId': 'group-1',
            'senderId': 'peer-sender',
            'senderDeviceId': 'sender-device-1',
            'transportPeerId': 'sender-device-1',
            'senderUsername': 'Sender',
            'keyEpoch': 1,
            'text': 'Device-bound replay',
            'timestamp': ts,
            'messageId': 'device-bound-replay-valid',
          }),
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      final stored = await msgRepo.getMessage('device-bound-replay-valid');
      expect(stored, isNotNull);
      expect(stored!.senderPeerId, 'peer-sender');
      expect(stored.transportPeerId, 'sender-device-1');
    },
  );

  test(
    'rejects offline replay from invalid registered sender device before message, event-log, or listener side effects',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-sender',
          username: 'Sender',
          role: MemberRole.writer,
          publicKey: 'sender-member-pk',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'sender-device-1',
              transportPeerId: 'sender-device-1',
              deviceSigningPublicKey: 'sender-device-pk-1',
              mlKemPublicKey: 'sender-device-mlkem-1',
            ),
          ],
          joinedAt: DateTime.utc(2026, 5, 1, 12),
        ),
      );
      final eventLogEntries = <Map<String, Object?>>[];
      final notifService = FakeNotificationService();
      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        notificationService: notifService,
        groupConversationTracker: ActiveConversationTracker(),
        getAppLifecycleState: () => AppLifecycleState.paused,
        appendGroupEventLogEntry:
            ({
              required groupId,
              required eventType,
              required sourcePeerId,
              required sourceEventId,
              required sourceTimestamp,
              required payload,
              createdAt,
            }) async {
              eventLogEntries.add({
                'groupId': groupId,
                'eventType': eventType,
                'sourcePeerId': sourcePeerId,
                'sourceEventId': sourceEventId,
                'payload': payload,
              });
              return eventLogEntries.last;
            },
      );
      final replayed = <GroupMessage>[];
      final subscription = listener.groupMessageStream.listen(replayed.add);
      addTearDown(() async {
        await subscription.cancel();
        listener.dispose();
      });

      final ts = DateTime.now().toUtc().toIso8601String();
      bridge.addPage('group-1', '', [
        {
          'from': 'sender-device-2',
          'message': jsonEncode({
            'groupId': 'group-1',
            'senderId': 'peer-sender',
            'senderDeviceId': 'sender-device-2',
            'transportPeerId': 'sender-device-2',
            'senderUsername': 'Sender',
            'keyEpoch': 1,
            'text': 'Invalid device replay',
            'timestamp': ts,
            'messageId': 'device-bound-replay-invalid',
          }),
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
      );

      await Future<void>.delayed(Duration.zero);

      expect(await msgRepo.getMessage('device-bound-replay-invalid'), isNull);
      expect(msgRepo.count, 0);
      expect(eventLogEntries, isEmpty);
      expect(replayed, isEmpty);
      expect(notifService.shown, isEmpty);
      expect(notifService.shownGeneric, isEmpty);
    },
  );

  test(
    'MS002 rejects offline inbox message when relay sender mismatches payload',
    () async {
      final ts = DateTime.now().toUtc().toIso8601String();
      bridge.addPage('group-1', '', [
        {
          'from': 'peer-attacker',
          'message': jsonEncode({
            'groupId': 'group-1',
            'senderId': 'peer-sender',
            'senderUsername': 'Sender',
            'keyEpoch': 1,
            'text': 'Spoofed inbox message',
            'timestamp': ts,
            'messageId': 'ms002-inbox-spoof',
          }),
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      expect(await msgRepo.getMessage('ms002-inbox-spoof'), isNull);
      expect(msgRepo.count, 0);
    },
  );

  test(
    'MS003 clamps far-future inbox timestamps before latest ordering',
    () async {
      final beforeReceive = DateTime.now().toUtc();
      final past = beforeReceive.subtract(const Duration(minutes: 10));
      final nearFuture = beforeReceive.add(const Duration(minutes: 3));
      final farFuture = beforeReceive.add(const Duration(days: 2));

      bridge.addPage('group-1', '', [
        {
          'from': 'peer-sender',
          'message': jsonEncode({
            'groupId': 'group-1',
            'senderId': 'peer-sender',
            'senderUsername': 'Sender',
            'keyEpoch': 1,
            'text': 'Far future inbox',
            'timestamp': farFuture.toIso8601String(),
            'messageId': 'ms003-inbox-far',
          }),
        },
        {
          'from': 'peer-sender',
          'message': jsonEncode({
            'groupId': 'group-1',
            'senderId': 'peer-sender',
            'senderUsername': 'Sender',
            'keyEpoch': 1,
            'text': 'Past inbox',
            'timestamp': past.toIso8601String(),
            'messageId': 'ms003-inbox-past',
          }),
        },
        {
          'from': 'peer-sender',
          'message': jsonEncode({
            'groupId': 'group-1',
            'senderId': 'peer-sender',
            'senderUsername': 'Sender',
            'keyEpoch': 1,
            'text': 'Near future inbox',
            'timestamp': nearFuture.toIso8601String(),
            'messageId': 'ms003-inbox-near',
          }),
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );
      final afterReceive = DateTime.now().toUtc();

      final page = await msgRepo.getMessagesPage('group-1');
      expect(page.map((message) => message.id), [
        'ms003-inbox-past',
        'ms003-inbox-far',
        'ms003-inbox-near',
      ]);

      final clamped = await msgRepo.getMessage('ms003-inbox-far');
      expect(clamped, isNotNull);
      expect(clamped!.timestamp.isBefore(farFuture), isTrue);
      expect(
        clamped.timestamp.isAfter(
          beforeReceive.subtract(const Duration(seconds: 1)),
        ),
        isTrue,
      );
      expect(
        clamped.timestamp.isBefore(
          afterReceive.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
      expect(
        (await msgRepo.getLatestMessage('group-1'))!.id,
        'ms003-inbox-near',
      );
    },
  );

  test('drain after watchdog restart retrieves messages exactly once', () async {
    final ts = DateTime.now().toUtc().toIso8601String();

    bridge.addPage('group-1', '', [
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Watchdog msg',
        'timestamp': ts,
        'messageId': 'msg-wd-1',
      },
    ], '');

    // Drain once (simulates first drain after watchdog restart).
    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );
    expect(msgRepo.count, 1);

    // Drain again (simulates second drain attempt — should be idempotent).
    // The bridge still returns the same message, but handleIncomingGroupMessage
    // should deduplicate by messageId.
    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );
    expect(msgRepo.count, 1, reason: 'Same message should not be saved twice');
  });

  test('drain after in-place recovery still allowed and idempotent', () async {
    final ts = DateTime.now().toUtc().toIso8601String();

    bridge.addPage('group-1', '', [
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'In-place msg',
        'timestamp': ts,
        'messageId': 'msg-ip-1',
      },
    ], '');

    // Drain once.
    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );
    expect(msgRepo.count, 1);

    // Drain again after in-place recovery — same messages are returned,
    // but should be deduplicated by messageId.
    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );
    expect(msgRepo.count, 1);
  });

  test(
    'drains groups concurrently so one slow inbox does not serially stall others',
    () async {
      final delayedBridge = _DelayedCursorInboxBridge();
      configureLegacyReplaySigning(delayedBridge);
      bridge = delayedBridge;

      final testGroup2 = GroupModel(
        id: 'group-2',
        name: 'Second Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/group-2',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'peer-admin',
        myRole: GroupRole.member,
      );
      await groupRepo.saveGroup(testGroup2);
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-2',
          peerId: 'peer-sender',
          username: 'Sender',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final ts = DateTime.now().toUtc().toIso8601String();
      delayedBridge.addPage('group-1', '', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Slow group 1',
          'timestamp': ts,
          'messageId': 'msg-group-1-slow',
        },
      ], '');
      delayedBridge.addPage('group-2', '', [
        {
          'groupId': 'group-2',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Slow group 2',
          'timestamp': ts,
          'messageId': 'msg-group-2-slow',
        },
      ], '');
      delayedBridge.addDelay('group-1', '', const Duration(milliseconds: 250));
      delayedBridge.addDelay('group-2', '', const Duration(milliseconds: 250));

      final stopwatch = Stopwatch()..start();
      await drainGroupOfflineInbox(
        bridge: delayedBridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );
      stopwatch.stop();

      expect(msgRepo.count, 2);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(400),
        reason:
            'Two 250ms group drains should overlap instead of running serially',
      );
    },
  );

  test(
    'replayed member_removed routes through listener cleanup instead of saving a chat row',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-self',
          username: 'Self',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
      );
      final removedGroups = <String>[];
      final sub = listener.groupRemovedStream.listen(removedGroups.add);
      addTearDown(() async {
        await sub.cancel();
        listener.dispose();
      });

      final ts = DateTime.now().toUtc().toIso8601String();
      bridge.addPage('group-1', '', [
        {
          'message': jsonEncode({
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({
              '__sys': 'member_removed',
              'member': {'peerId': 'peer-self', 'username': 'Self'},
              'groupConfig': {
                'name': 'Test Group',
                'groupType': 'chat',
                'members': [
                  {'peerId': 'peer-admin', 'role': 'admin'},
                ],
                'createdBy': 'peer-admin',
                'createdAt': ts,
              },
            }),
            'timestamp': ts,
          }),
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
      );

      expect(await groupRepo.getGroup('group-1'), isNull);
      expect(bridge.commandLog, contains('group:leave'));
      expect(removedGroups, ['group-1']);
      expect(msgRepo.count, 0);
    },
  );

  test(
    'replayed self-removal cuts off later queued inbox traffic for that group',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-self',
          username: 'Self',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
      );
      final removedGroups = <String>[];
      final sub = listener.groupRemovedStream.listen(removedGroups.add);
      addTearDown(() async {
        await sub.cancel();
        listener.dispose();
      });

      final removedAt = DateTime.now().toUtc().toIso8601String();
      final samePageQueuedAt = DateTime.now()
          .toUtc()
          .add(const Duration(seconds: 1))
          .toIso8601String();
      final nextPageQueuedAt = DateTime.now()
          .toUtc()
          .add(const Duration(seconds: 2))
          .toIso8601String();

      bridge.addPage('group-1', '', [
        {
          'message': jsonEncode({
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({
              '__sys': 'member_removed',
              'member': {'peerId': 'peer-self', 'username': 'Self'},
              'groupConfig': {
                'name': 'Test Group',
                'groupType': 'chat',
                'members': [
                  {'peerId': 'peer-admin', 'role': 'admin'},
                ],
                'createdBy': 'peer-admin',
                'createdAt': removedAt,
              },
            }),
            'timestamp': removedAt,
            'messageId': 'msg-remove-self',
          }),
        },
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Queued after removal on same page',
          'timestamp': samePageQueuedAt,
          'messageId': 'msg-after-removal-same-page',
        },
      ], 'cursor-after-removal');

      bridge.addPage('group-1', 'cursor-after-removal', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Queued after removal on next page',
          'timestamp': nextPageQueuedAt,
          'messageId': 'msg-after-removal-next-page',
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
      );

      expect(await groupRepo.getGroup('group-1'), isNull);
      expect(bridge.commandLog, contains('group:leave'));
      expect(removedGroups, ['group-1']);
      expect(
        msgRepo.count,
        0,
        reason:
            'Queued post-removal inbox traffic must not be persisted for the removed peer',
      );

      final retrieveCount = bridge.commandLog
          .where((command) => command == 'group:inboxRetrieveCursor')
          .length;
      expect(
        retrieveCount,
        1,
        reason:
            'Drain should stop before later cursor pages once replayed self-removal deletes the group',
      );
    },
  );

  test(
    'GI-018 removed member offline replay keeps pre-removal message and stops at removal cutoff',
    () async {
      await saveDefaultReplayKey();
      final groupCreatedAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 10),
      );
      final beforeRemovalAt = groupCreatedAt.add(const Duration(minutes: 1));
      final removedAt = groupCreatedAt.add(const Duration(minutes: 2));
      final samePagePostRemovalAt = groupCreatedAt.add(
        const Duration(minutes: 3),
      );
      final nextPagePostRemovalAt = groupCreatedAt.add(
        const Duration(minutes: 4),
      );

      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-self',
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-self',
          joinedAt: groupCreatedAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          publicKey: 'pk-admin',
          joinedAt: groupCreatedAt,
        ),
      );

      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
      );
      final removedGroups = <String>[];
      final sub = listener.groupRemovedStream.listen(removedGroups.add);
      addTearDown(() async {
        await sub.cancel();
        listener.dispose();
      });

      const beforeMessageId = 'gi018-before-removal';
      const samePagePostRemovalMessageId = 'gi018-after-removal-same-page';
      const nextPagePostRemovalMessageId = 'gi018-after-removal-next-page';
      const beforeText = 'GI-018 before Charlie removal';
      const samePagePostRemovalText =
          'GI-018 same-page content after Charlie removal';
      const nextPagePostRemovalText =
          'GI-018 next-page content after Charlie removal';

      final removalPayload = {
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 1,
        'text': jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-self', 'username': 'Charlie'},
          'removedAt': removedAt.toIso8601String(),
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {'peerId': 'peer-admin', 'role': 'admin'},
              {'peerId': 'peer-sender', 'role': 'writer'},
            ],
            'createdBy': 'peer-admin',
            'createdAt': groupCreatedAt.toIso8601String(),
          },
        }),
        'timestamp': removedAt.toIso8601String(),
        'messageId': 'gi018-remove-self',
      };

      final removalReplay = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: jsonEncode(removalPayload),
        messageId: 'gi018-remove-self',
        senderPeerId: 'peer-admin',
        senderPublicKey: 'pk-admin',
        senderPrivateKey: 'sk-admin',
      );

      bridge.addPage('group-1', '', [
        await signedRelayMessage(
          id: beforeMessageId,
          text: beforeText,
          timestamp: beforeRemovalAt,
        ),
      ], 'cursor-removal');
      bridge.addPage('group-1', 'cursor-removal', [
        {
          'from': 'peer-admin',
          'message': removalReplay,
          'timestamp': removedAt.millisecondsSinceEpoch,
        },
        await signedRelayMessage(
          id: samePagePostRemovalMessageId,
          text: samePagePostRemovalText,
          timestamp: samePagePostRemovalAt,
          senderId: 'peer-admin',
          senderPublicKey: 'pk-admin',
          senderPrivateKey: 'sk-admin',
          senderUsername: 'Admin',
        ),
      ], 'cursor-after-removal');
      bridge.addPage('group-1', 'cursor-after-removal', [
        await signedRelayMessage(
          id: nextPagePostRemovalMessageId,
          text: nextPagePostRemovalText,
          timestamp: nextPagePostRemovalAt,
          senderId: 'peer-admin',
          senderPublicKey: 'pk-admin',
          senderPrivateKey: 'sk-admin',
          senderUsername: 'Admin',
        ),
      ], '');

      bridge.commandLog.clear();
      bridge.sentMessages.clear();

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
        selfPeerId: 'peer-self',
      );

      final beforeMessage = await msgRepo.getMessage(beforeMessageId);
      expect(beforeMessage, isNotNull);
      expect(beforeMessage!.text, beforeText);
      expect(beforeMessage.senderPeerId, 'peer-sender');
      expect(beforeMessage.timestamp, beforeRemovalAt);
      expect(await msgRepo.getMessage(samePagePostRemovalMessageId), isNull);
      expect(await msgRepo.getMessage(nextPagePostRemovalMessageId), isNull);
      expect(await groupRepo.getGroup('group-1'), isNull);
      expect(bridge.commandLog, contains('group:leave'));
      expect(removedGroups, ['group-1']);

      final cursorRequests = bridge.sentMessages
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .where((message) => message['cmd'] == 'group:inboxRetrieveCursor')
          .map(
            (message) =>
                (message['payload'] as Map<String, dynamic>)['cursor']
                    as String? ??
                '',
          )
          .toList();
      expect(cursorRequests, ['', 'cursor-removal']);

      final decryptPlaintexts = bridge.sentMessages
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .where((message) => message['cmd'] == 'group.decrypt')
          .map(
            (message) =>
                ((message['payload'] as Map<String, dynamic>)['ciphertext']
                    as String?) ??
                '',
          )
          .toList();
      final uniqueDecryptPlaintexts = decryptPlaintexts.toSet();
      expect(uniqueDecryptPlaintexts, hasLength(2));
      expect(
        uniqueDecryptPlaintexts.where(
          (plaintext) => plaintext.contains(beforeText),
        ),
        hasLength(1),
      );
      expect(
        uniqueDecryptPlaintexts.where(
          (plaintext) => plaintext.contains('member_removed'),
        ),
        hasLength(1),
      );
      expect(
        uniqueDecryptPlaintexts.where(
          (plaintext) => plaintext.contains(samePagePostRemovalText),
        ),
        isEmpty,
      );
      expect(
        uniqueDecryptPlaintexts.where(
          (plaintext) => plaintext.contains(nextPagePostRemovalText),
        ),
        isEmpty,
      );
    },
  );

  test(
    'replayed member_removed lets remaining peers accept only removed-sender inbox messages from before removedAt',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-self',
          username: 'Self',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
      );
      addTearDown(listener.dispose);

      final removedAt = DateTime.now().toUtc();
      final beforeCutoff = removedAt
          .subtract(const Duration(milliseconds: 1))
          .toIso8601String();
      final atCutoff = removedAt.toIso8601String();

      bridge.addPage('group-1', '', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Before cutoff replay',
          'timestamp': beforeCutoff,
          'messageId': 'msg-before-cutoff-replay',
        },
        {
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': jsonEncode({
            '__sys': 'member_removed',
            'member': {'peerId': 'peer-sender', 'username': 'Sender'},
            'removedAt': removedAt.toIso8601String(),
            'groupConfig': {
              'name': 'Test Group',
              'groupType': 'chat',
              'members': [
                {'peerId': 'peer-admin', 'role': 'admin'},
                {'peerId': 'peer-self', 'role': 'writer'},
              ],
              'createdBy': 'peer-admin',
              'createdAt': removedAt.toIso8601String(),
            },
          }),
          'timestamp': removedAt.toIso8601String(),
          'messageId': 'msg-remove-sender',
        },
      ], 'cursor-after-cutoff');

      bridge.addPage('group-1', 'cursor-after-cutoff', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'At cutoff replay',
          'timestamp': atCutoff,
          'messageId': 'msg-at-cutoff-replay',
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
      );

      expect(await groupRepo.getMember('group-1', 'peer-sender'), isNull);

      final messages = await msgRepo.getMessagesPage('group-1');
      expect(
        messages.where((message) => message.text == 'Before cutoff replay'),
        hasLength(1),
      );
      expect(
        messages.where((message) => message.text == 'At cutoff replay'),
        isEmpty,
      );
      expect(
        messages.where(
          (message) =>
              message.id.startsWith('sys-member_removed:group-1:peer-sender:'),
        ),
        hasLength(1),
      );

      final retrieveCount = bridge.commandLog
          .where((command) => command == 'group:inboxRetrieveCursor')
          .length;
      expect(
        retrieveCount,
        2,
        reason:
            'Drain should carry the persisted cutoff across later cursor pages',
      );
    },
  );

  test(
    'GI-025 valid pre-removal replay after removal is accepted only as history',
    () async {
      await saveDefaultReplayKey();

      final joinedAt = testGroup.createdAt.toUtc();
      final removedAt = joinedAt.add(const Duration(minutes: 1));
      final beforeRemovalAt = removedAt.subtract(
        const Duration(milliseconds: 1),
      );
      final afterRemovalAt = removedAt.add(const Duration(milliseconds: 1));

      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-self',
          username: 'Self',
          role: MemberRole.writer,
          publicKey: 'pk-self',
          joinedAt: joinedAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          publicKey: 'pk-admin',
          joinedAt: joinedAt,
        ),
      );

      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink((payload) {
        flowEvents.add(Map<String, dynamic>.from(payload));
      });
      addTearDown(() {
        debugSetFlowEventSink(null);
      });

      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
      );
      final replayedMessages = <GroupMessage>[];
      final subscription = listener.groupMessageStream.listen(
        replayedMessages.add,
      );
      addTearDown(() async {
        await subscription.cancel();
        listener.dispose();
      });

      const beforeMessageId = 'msg-gi025-pre-removal-replay';
      const afterMessageId = 'msg-gi025-post-removal-replay';

      final removalReplay = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        senderPeerId: 'peer-admin',
        senderPublicKey: 'pk-admin',
        senderPrivateKey: 'sk-admin',
        messageId: 'msg-gi025-remove-sender',
        plaintext: jsonEncode({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 1,
          'text': jsonEncode({
            '__sys': 'member_removed',
            'member': {'peerId': 'peer-sender', 'username': 'Sender'},
            'removedAt': removedAt.toIso8601String(),
            'groupConfig': {
              'name': 'Test Group',
              'groupType': 'chat',
              'members': [
                {'peerId': 'peer-admin', 'role': 'admin'},
                {'peerId': 'peer-self', 'role': 'writer'},
              ],
              'createdBy': 'peer-admin',
              'createdAt': testGroup.createdAt.toIso8601String(),
            },
          }),
          'timestamp': removedAt.toIso8601String(),
          'messageId': 'msg-gi025-remove-sender',
        }),
      );
      final beforeReplay = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        messageId: beforeMessageId,
        plaintext: jsonEncode({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'GI-025 old history replay',
          'timestamp': beforeRemovalAt.toIso8601String(),
          'messageId': beforeMessageId,
        }),
      );
      final afterReplay = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        messageId: afterMessageId,
        plaintext: jsonEncode({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'GI-025 removed-window replay',
          'timestamp': afterRemovalAt.toIso8601String(),
          'messageId': afterMessageId,
        }),
      );

      bridge.addPage('group-1', '', [
        {'from': 'peer-admin', 'message': removalReplay, 'timestamp': 1},
      ], 'cursor-after-removal');
      bridge.addPage('group-1', 'cursor-after-removal', [
        {'from': 'peer-sender', 'message': beforeReplay, 'timestamp': 2},
        {'from': 'peer-sender', 'message': beforeReplay, 'timestamp': 3},
        {'from': 'peer-sender', 'message': afterReplay, 'timestamp': 4},
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
      );
      await Future<void>.delayed(Duration.zero);

      expect(await groupRepo.getMember('group-1', 'peer-sender'), isNull);

      final beforeStored = await msgRepo.getMessage(beforeMessageId);
      expect(beforeStored, isNotNull);
      expect(beforeStored!.text, 'GI-025 old history replay');
      expect(beforeStored.timestamp, beforeRemovalAt);
      expect(beforeStored.senderPeerId, 'peer-sender');
      expect(beforeStored.status, 'delivered');
      expect(beforeStored.isIncoming, isTrue);

      expect(await msgRepo.getMessage(afterMessageId), isNull);
      expect(
        (await msgRepo.getMessagesPage(
          'group-1',
        )).where((message) => message.text == 'GI-025 old history replay'),
        hasLength(1),
      );
      expect(
        replayedMessages.where((message) => message.id == beforeMessageId),
        hasLength(1),
      );
      expect(
        replayedMessages.where((message) => message.id == afterMessageId),
        isEmpty,
      );

      expect(
        flowEvents.where(
          (event) =>
              event['event'] == 'GROUP_HANDLE_INCOMING_MSG_DUPLICATE' &&
              (event['details'] as Map<String, dynamic>)['dedupeBy'] ==
                  'messageId',
        ),
        hasLength(1),
      );
      final removedWindowEvents = flowEvents.where(
        (event) =>
            event['event'] == 'GROUP_HANDLE_INCOMING_MSG_REMOVED_AFTER_CUTOFF',
      );
      expect(removedWindowEvents, hasLength(1));
      expect(
        (removedWindowEvents.single['details']
            as Map<String, dynamic>)['cutoffAt'],
        removedAt.toIso8601String(),
      );

      final cursorRequests = bridge.sentMessages
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .where((message) => message['cmd'] == 'group:inboxRetrieveCursor')
          .map(
            (message) =>
                (message['payload'] as Map<String, dynamic>)['cursor']
                    as String? ??
                '',
          )
          .toList();
      expect(cursorRequests, ['', 'cursor-after-removal']);
    },
  );

  test(
    'GM-033 replay resume rejects removed-window messages after self re-add',
    () async {
      const groupId = 'group-1';
      const alicePeerId = 'peer-alice';
      const bobPeerId = 'peer-bob';
      const charliePeerId = 'peer-charlie';
      const beforeMessageId = 'gm033-before-removal';
      const removedWindowMessageId = 'gm033-removed-window';
      const postReaddMessageId = 'gm033-post-readd-live';
      const beforeText = 'GM-033 before Charlie removal';
      const removedWindowText = 'GM-033 while Charlie removed';
      const postReaddText = 'GM-033 after Charlie re-add';
      final groupCreatedAt = DateTime.utc(2026, 5, 11, 12);
      final beforeRemovalAt = groupCreatedAt.add(const Duration(minutes: 1));
      final removedAt = groupCreatedAt.add(const Duration(minutes: 2));
      final removedWindowAt = groupCreatedAt.add(const Duration(minutes: 3));
      final readdAt = groupCreatedAt.add(const Duration(minutes: 4));
      final postReaddAt = groupCreatedAt.add(const Duration(minutes: 5));
      final keyEpoch1 = GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'gm033-key-epoch-1',
        createdAt: groupCreatedAt,
      );
      final keyEpoch2 = GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 2,
        encryptedKey: 'gm033-key-epoch-2',
        createdAt: readdAt,
      );

      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink((payload) {
        flowEvents.add(Map<String, dynamic>.from(payload));
      });
      addTearDown(() {
        debugSetFlowEventSink(null);
      });

      GroupMember member({
        required String peerId,
        required String username,
        required MemberRole role,
        required DateTime joinedAt,
      }) {
        return GroupMember(
          groupId: groupId,
          peerId: peerId,
          username: username,
          role: role,
          publicKey: 'pk-$peerId',
          mlKemPublicKey: 'mlkem-$peerId',
          joinedAt: joinedAt,
        );
      }

      final aliceMember = member(
        peerId: alicePeerId,
        username: 'Alice',
        role: MemberRole.admin,
        joinedAt: groupCreatedAt,
      );
      final bobMember = member(
        peerId: bobPeerId,
        username: 'Bob',
        role: MemberRole.writer,
        joinedAt: groupCreatedAt.add(const Duration(seconds: 1)),
      );
      final initialCharlieMember = member(
        peerId: charliePeerId,
        username: 'Charlie',
        role: MemberRole.writer,
        joinedAt: groupCreatedAt.add(const Duration(seconds: 2)),
      );
      final readdedCharlieMember = member(
        peerId: charliePeerId,
        username: 'Charlie',
        role: MemberRole.writer,
        joinedAt: readdAt,
      );
      final baseGroup = testGroup.copyWith(
        name: 'GM-033 Group',
        createdAt: groupCreatedAt,
        createdBy: alicePeerId,
        myRole: GroupRole.member,
      );

      await groupRepo.updateGroup(baseGroup);
      await groupRepo.removeMember(groupId, 'peer-sender');
      for (final groupMember in <GroupMember>[
        aliceMember,
        bobMember,
        initialCharlieMember,
      ]) {
        await groupRepo.saveMember(groupMember);
      }
      await groupRepo.saveKey(keyEpoch1);

      Future<Map<String, dynamic>> replayMessage({
        required String messageId,
        required String text,
        required DateTime timestamp,
        required GroupKeyInfo keyInfo,
      }) async {
        final replayEnvelope = await buildGroupOfflineReplayEnvelope(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintext: jsonEncode({
            'groupId': groupId,
            'senderId': alicePeerId,
            'senderUsername': 'Alice',
            'keyEpoch': keyInfo.keyGeneration,
            'text': text,
            'timestamp': timestamp.toIso8601String(),
            'messageId': messageId,
          }),
          messageId: messageId,
          senderPeerId: alicePeerId,
          senderPublicKey: 'pk-$alicePeerId',
          senderPrivateKey: 'sk-$alicePeerId',
          keyInfo: keyInfo,
          recipientPeerIds: const <String>[bobPeerId, charliePeerId],
        );
        return <String, dynamic>{
          'from': alicePeerId,
          'message': replayEnvelope,
          'timestamp': timestamp.microsecondsSinceEpoch,
        };
      }

      final beforeReplay = await replayMessage(
        messageId: beforeMessageId,
        text: beforeText,
        timestamp: beforeRemovalAt,
        keyInfo: keyEpoch1,
      );
      final removedWindowReplay = await replayMessage(
        messageId: removedWindowMessageId,
        text: removedWindowText,
        timestamp: removedWindowAt,
        keyInfo: keyEpoch1,
      );
      final postReaddReplay = await replayMessage(
        messageId: postReaddMessageId,
        text: postReaddText,
        timestamp: postReaddAt,
        keyInfo: keyEpoch2,
      );

      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => charliePeerId,
      );
      addTearDown(listener.dispose);
      final pendingRepo = _InMemoryGroupPendingKeyRepairRepository();
      final repairRequests = <GroupKeyRepairRequest>[];

      bridge.addPage(groupId, '', [beforeReplay], 'gm033-page-2');
      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
        pendingKeyRepairRepo: pendingRepo,
        requestGroupKeyRepair: repairRequests.add,
        selfPeerId: charliePeerId,
        drainAllPages: false,
      );

      expect(await msgRepo.getMessage(beforeMessageId), isNotNull);
      expect(await msgRepo.getInboxCursor(groupId), 'gm033-page-2');

      final removalGroupConfig = buildGroupConfigPayload(
        baseGroup.copyWith(lastMembershipEventAt: removedAt),
        <GroupMember>[aliceMember, bobMember],
        configVersionOverride: removedAt,
      );
      await listener.handleReplayEnvelope({
        'groupId': groupId,
        'senderId': alicePeerId,
        'senderUsername': 'Alice',
        'keyEpoch': 0,
        'text': jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': charliePeerId, 'username': 'Charlie'},
          'removedAt': removedAt.toIso8601String(),
          'groupConfig': removalGroupConfig,
        }),
        'timestamp': removedAt.toIso8601String(),
        'messageId': 'gm033-remove-charlie',
      }, rethrowOnError: true);

      expect(await groupRepo.getGroup(groupId), isNull);
      expect(
        await msgRepo.getLatestRemovalTimestampForSender(
          groupId,
          charliePeerId,
        ),
        removedAt,
        reason:
            'Self-removal during replay must persist a cutoff before local group cleanup',
      );

      await groupRepo.saveGroup(
        baseGroup.copyWith(lastMembershipEventAt: readdAt),
      );
      for (final groupMember in <GroupMember>[
        aliceMember,
        bobMember,
        readdedCharlieMember,
      ]) {
        await groupRepo.saveMember(groupMember);
      }
      await groupRepo.saveKey(keyEpoch1);
      await groupRepo.saveKey(keyEpoch2);
      bridge.addPage(groupId, 'gm033-page-2', [
        removedWindowReplay,
        postReaddReplay,
        removedWindowReplay,
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
        pendingKeyRepairRepo: pendingRepo,
        requestGroupKeyRepair: repairRequests.add,
        selfPeerId: charliePeerId,
      );

      final messages = await msgRepo.getMessagesPage(groupId);
      expect(
        messages.where((message) => message.id == beforeMessageId),
        hasLength(1),
      );
      expect(
        messages.where((message) => message.id == removedWindowMessageId),
        isEmpty,
      );
      expect(
        messages.where((message) => message.text == removedWindowText),
        isEmpty,
      );
      expect(
        messages.where((message) => message.id == postReaddMessageId),
        hasLength(1),
      );
      expect(
        messages
            .singleWhere((message) => message.id == postReaddMessageId)
            .text,
        postReaddText,
      );
      expect(await msgRepo.getInboxCursor(groupId), '');
      expect(
        pendingRepo.repairs.values.where(
          (repair) => repair.messageId == removedWindowMessageId,
        ),
        isEmpty,
      );
      expect(
        repairRequests.where(
          (request) => request.messageId == removedWindowMessageId,
        ),
        isEmpty,
      );
      expect(
        flowEvents.where(
          (event) =>
              event['event'] ==
              'GROUP_HANDLE_INCOMING_MSG_SELF_REMOVED_WINDOW_AFTER_REJOIN',
        ),
        hasLength(greaterThanOrEqualTo(1)),
      );

      final cursorCommands = bridge.sentMessages
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .where((message) => message['cmd'] == 'group:inboxRetrieveCursor')
          .map(
            (message) =>
                (message['payload'] as Map<String, dynamic>)['cursor']
                    as String? ??
                '',
          )
          .toList(growable: false);
      expect(cursorCommands, containsAllInOrder(<String>['', 'gm033-page-2']));
    },
  );

  test(
    'GK-023 re-added member skips removed-window replay and renders post-readd replay',
    () async {
      const groupId = 'group-1';
      const alicePeerId = 'peer-alice';
      const bobPeerId = 'peer-bob';
      const charliePeerId = 'peer-charlie';
      const beforeMessageId = 'gk023-before-removal';
      const removedWindowMessageId = 'gk023-removed-window';
      const postReaddMessageId = 'gk023-post-readd-replay';
      const beforeText = 'GK-023 before Charlie removal';
      const removedWindowText = 'GK-023 while Charlie removed';
      const postReaddText = 'GK-023 after Charlie re-add';
      final groupCreatedAt = DateTime.utc(2026, 5, 12, 12);
      final beforeRemovalAt = groupCreatedAt.add(const Duration(minutes: 1));
      final removedAt = groupCreatedAt.add(const Duration(minutes: 2));
      final removedWindowAt = groupCreatedAt.add(const Duration(minutes: 3));
      final readdAt = groupCreatedAt.add(const Duration(minutes: 4));
      final postReaddAt = groupCreatedAt.add(const Duration(minutes: 5));
      final keyEpoch1 = GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'gk023-key-epoch-1',
        createdAt: groupCreatedAt,
      );
      final keyEpoch2 = GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 2,
        encryptedKey: 'gk023-key-epoch-2',
        createdAt: readdAt,
      );

      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink((payload) {
        flowEvents.add(Map<String, dynamic>.from(payload));
      });
      addTearDown(() {
        debugSetFlowEventSink(null);
      });

      GroupMember member({
        required String peerId,
        required String username,
        required MemberRole role,
        required DateTime joinedAt,
      }) {
        return GroupMember(
          groupId: groupId,
          peerId: peerId,
          username: username,
          role: role,
          publicKey: 'pk-$peerId',
          mlKemPublicKey: 'mlkem-$peerId',
          joinedAt: joinedAt,
        );
      }

      final aliceMember = member(
        peerId: alicePeerId,
        username: 'Alice',
        role: MemberRole.admin,
        joinedAt: groupCreatedAt,
      );
      final bobMember = member(
        peerId: bobPeerId,
        username: 'Bob',
        role: MemberRole.writer,
        joinedAt: groupCreatedAt.add(const Duration(seconds: 1)),
      );
      final initialCharlieMember = member(
        peerId: charliePeerId,
        username: 'Charlie',
        role: MemberRole.writer,
        joinedAt: groupCreatedAt.add(const Duration(seconds: 2)),
      );
      final readdedCharlieMember = member(
        peerId: charliePeerId,
        username: 'Charlie',
        role: MemberRole.writer,
        joinedAt: readdAt,
      );
      final baseGroup = testGroup.copyWith(
        name: 'GK-023 Group',
        createdAt: groupCreatedAt,
        createdBy: alicePeerId,
        myRole: GroupRole.member,
      );

      await groupRepo.updateGroup(baseGroup);
      await groupRepo.removeMember(groupId, 'peer-sender');
      for (final groupMember in <GroupMember>[
        aliceMember,
        bobMember,
        initialCharlieMember,
      ]) {
        await groupRepo.saveMember(groupMember);
      }
      await groupRepo.saveKey(keyEpoch1);

      Future<Map<String, dynamic>> replayMessage({
        required String messageId,
        required String text,
        required DateTime timestamp,
        required GroupKeyInfo keyInfo,
      }) async {
        final replayEnvelope = await buildGroupOfflineReplayEnvelope(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintext: jsonEncode({
            'groupId': groupId,
            'senderId': alicePeerId,
            'senderUsername': 'Alice',
            'keyEpoch': keyInfo.keyGeneration,
            'text': text,
            'timestamp': timestamp.toIso8601String(),
            'messageId': messageId,
          }),
          messageId: messageId,
          senderPeerId: alicePeerId,
          senderPublicKey: 'pk-$alicePeerId',
          senderPrivateKey: 'sk-$alicePeerId',
          keyInfo: keyInfo,
          recipientPeerIds: const <String>[bobPeerId, charliePeerId],
        );
        return <String, dynamic>{
          'from': alicePeerId,
          'message': replayEnvelope,
          'timestamp': timestamp.microsecondsSinceEpoch,
        };
      }

      final beforeReplay = await replayMessage(
        messageId: beforeMessageId,
        text: beforeText,
        timestamp: beforeRemovalAt,
        keyInfo: keyEpoch1,
      );
      final removedWindowReplay = await replayMessage(
        messageId: removedWindowMessageId,
        text: removedWindowText,
        timestamp: removedWindowAt,
        keyInfo: keyEpoch1,
      );
      final postReaddReplay = await replayMessage(
        messageId: postReaddMessageId,
        text: postReaddText,
        timestamp: postReaddAt,
        keyInfo: keyEpoch2,
      );

      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => charliePeerId,
      );
      addTearDown(listener.dispose);
      final pendingRepo = _InMemoryGroupPendingKeyRepairRepository();
      final repairRequests = <GroupKeyRepairRequest>[];

      bridge.addPage(groupId, '', [beforeReplay], 'gk023-page-2');
      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
        pendingKeyRepairRepo: pendingRepo,
        requestGroupKeyRepair: repairRequests.add,
        selfPeerId: charliePeerId,
        drainAllPages: false,
      );

      expect(await msgRepo.getMessage(beforeMessageId), isNotNull);
      expect(await msgRepo.getInboxCursor(groupId), 'gk023-page-2');

      final removalGroupConfig = buildGroupConfigPayload(
        baseGroup.copyWith(lastMembershipEventAt: removedAt),
        <GroupMember>[aliceMember, bobMember],
        configVersionOverride: removedAt,
      );
      await listener.handleReplayEnvelope({
        'groupId': groupId,
        'senderId': alicePeerId,
        'senderUsername': 'Alice',
        'keyEpoch': 0,
        'text': jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': charliePeerId, 'username': 'Charlie'},
          'removedAt': removedAt.toIso8601String(),
          'groupConfig': removalGroupConfig,
        }),
        'timestamp': removedAt.toIso8601String(),
        'messageId': 'gk023-remove-charlie',
      }, rethrowOnError: true);

      expect(await groupRepo.getGroup(groupId), isNull);
      expect(
        await msgRepo.getLatestRemovalTimestampForSender(
          groupId,
          charliePeerId,
        ),
        removedAt,
        reason:
            'Self-removal during replay must persist a cutoff before local group cleanup',
      );

      await groupRepo.saveGroup(
        baseGroup.copyWith(lastMembershipEventAt: readdAt),
      );
      for (final groupMember in <GroupMember>[
        aliceMember,
        bobMember,
        readdedCharlieMember,
      ]) {
        await groupRepo.saveMember(groupMember);
      }
      await groupRepo.saveKey(keyEpoch1);
      await groupRepo.saveKey(keyEpoch2);
      bridge.addPage(groupId, 'gk023-page-2', [
        removedWindowReplay,
        postReaddReplay,
        removedWindowReplay,
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
        pendingKeyRepairRepo: pendingRepo,
        requestGroupKeyRepair: repairRequests.add,
        selfPeerId: charliePeerId,
      );

      final messages = await msgRepo.getMessagesPage(groupId);
      expect(
        messages.where((message) => message.id == beforeMessageId),
        hasLength(1),
      );
      expect(
        messages.where((message) => message.id == removedWindowMessageId),
        isEmpty,
      );
      expect(
        messages.where((message) => message.text == removedWindowText),
        isEmpty,
      );
      expect(
        messages.where((message) => message.id == postReaddMessageId),
        hasLength(1),
      );
      expect(
        messages
            .singleWhere((message) => message.id == postReaddMessageId)
            .text,
        postReaddText,
      );
      expect(await msgRepo.getInboxCursor(groupId), '');
      expect(
        pendingRepo.repairs.values.where(
          (repair) => repair.messageId == removedWindowMessageId,
        ),
        isEmpty,
      );
      expect(
        repairRequests.where(
          (request) => request.messageId == removedWindowMessageId,
        ),
        isEmpty,
      );
      expect(
        flowEvents.where(
          (event) =>
              event['event'] ==
              'GROUP_HANDLE_INCOMING_MSG_SELF_REMOVED_WINDOW_AFTER_REJOIN',
        ),
        hasLength(greaterThanOrEqualTo(1)),
      );

      final cursorCommands = bridge.sentMessages
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .where((message) => message['cmd'] == 'group:inboxRetrieveCursor')
          .map(
            (message) =>
                (message['payload'] as Map<String, dynamic>)['cursor']
                    as String? ??
                '',
          )
          .toList(growable: false);
      expect(cursorCommands, containsAllInOrder(<String>['', 'gk023-page-2']));
    },
  );

  test(
    'GI-019 re-added member replay keeps pre-remove skips removed-window and renders post-readd',
    () async {
      const groupId = 'group-1';
      const alicePeerId = 'peer-alice';
      const bobPeerId = 'peer-bob';
      const charliePeerId = 'peer-charlie';
      const beforeMessageId = 'gi019-before-removal';
      const removedWindowMessageId = 'gi019-removed-window';
      const postReaddMessageId = 'gi019-post-readd-replay';
      const beforeText = 'GI-019 before Charlie removal';
      const removedWindowText = 'GI-019 while Charlie removed';
      const postReaddText = 'GI-019 after Charlie re-add';
      final groupCreatedAt = DateTime.utc(2026, 5, 12, 16);
      final beforeRemovalAt = groupCreatedAt.add(const Duration(minutes: 1));
      final removedAt = groupCreatedAt.add(const Duration(minutes: 2));
      final removedWindowAt = groupCreatedAt.add(const Duration(minutes: 3));
      final readdAt = groupCreatedAt.add(const Duration(minutes: 4));
      final postReaddAt = groupCreatedAt.add(const Duration(minutes: 5));
      final keyEpoch1 = GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'gi019-key-epoch-1',
        createdAt: groupCreatedAt,
      );
      final keyEpoch2 = GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 2,
        encryptedKey: 'gi019-key-epoch-2',
        createdAt: readdAt,
      );

      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink((payload) {
        flowEvents.add(Map<String, dynamic>.from(payload));
      });
      addTearDown(() {
        debugSetFlowEventSink(null);
      });

      GroupMember member({
        required String peerId,
        required String username,
        required MemberRole role,
        required DateTime joinedAt,
      }) {
        return GroupMember(
          groupId: groupId,
          peerId: peerId,
          username: username,
          role: role,
          publicKey: 'pk-$peerId',
          mlKemPublicKey: 'mlkem-$peerId',
          joinedAt: joinedAt,
        );
      }

      final aliceMember = member(
        peerId: alicePeerId,
        username: 'Alice',
        role: MemberRole.admin,
        joinedAt: groupCreatedAt,
      );
      final bobMember = member(
        peerId: bobPeerId,
        username: 'Bob',
        role: MemberRole.writer,
        joinedAt: groupCreatedAt.add(const Duration(seconds: 1)),
      );
      final initialCharlieMember = member(
        peerId: charliePeerId,
        username: 'Charlie',
        role: MemberRole.writer,
        joinedAt: groupCreatedAt.add(const Duration(seconds: 2)),
      );
      final readdedCharlieMember = member(
        peerId: charliePeerId,
        username: 'Charlie',
        role: MemberRole.writer,
        joinedAt: readdAt,
      );
      final baseGroup = testGroup.copyWith(
        name: 'GI-019 Group',
        createdAt: groupCreatedAt,
        createdBy: alicePeerId,
        myRole: GroupRole.member,
      );

      await groupRepo.updateGroup(baseGroup);
      await groupRepo.removeMember(groupId, 'peer-sender');
      for (final groupMember in <GroupMember>[
        aliceMember,
        bobMember,
        initialCharlieMember,
      ]) {
        await groupRepo.saveMember(groupMember);
      }
      await groupRepo.saveKey(keyEpoch1);

      Future<Map<String, dynamic>> replayMessage({
        required String messageId,
        required String text,
        required DateTime timestamp,
        required GroupKeyInfo keyInfo,
      }) async {
        final replayEnvelope = await buildGroupOfflineReplayEnvelope(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintext: jsonEncode({
            'groupId': groupId,
            'senderId': alicePeerId,
            'senderUsername': 'Alice',
            'keyEpoch': keyInfo.keyGeneration,
            'text': text,
            'timestamp': timestamp.toIso8601String(),
            'messageId': messageId,
          }),
          messageId: messageId,
          senderPeerId: alicePeerId,
          senderPublicKey: 'pk-$alicePeerId',
          senderPrivateKey: 'sk-$alicePeerId',
          keyInfo: keyInfo,
          recipientPeerIds: const <String>[bobPeerId, charliePeerId],
        );
        return <String, dynamic>{
          'from': alicePeerId,
          'message': replayEnvelope,
          'timestamp': timestamp.microsecondsSinceEpoch,
        };
      }

      final beforeReplay = await replayMessage(
        messageId: beforeMessageId,
        text: beforeText,
        timestamp: beforeRemovalAt,
        keyInfo: keyEpoch1,
      );
      final removedWindowReplay = await replayMessage(
        messageId: removedWindowMessageId,
        text: removedWindowText,
        timestamp: removedWindowAt,
        keyInfo: keyEpoch1,
      );
      final postReaddReplay = await replayMessage(
        messageId: postReaddMessageId,
        text: postReaddText,
        timestamp: postReaddAt,
        keyInfo: keyEpoch2,
      );

      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => charliePeerId,
      );
      addTearDown(listener.dispose);
      final pendingRepo = _InMemoryGroupPendingKeyRepairRepository();
      final repairRequests = <GroupKeyRepairRequest>[];

      bridge.addPage(groupId, '', [beforeReplay], 'gi019-page-2');
      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
        pendingKeyRepairRepo: pendingRepo,
        requestGroupKeyRepair: repairRequests.add,
        selfPeerId: charliePeerId,
        drainAllPages: false,
      );

      expect(await msgRepo.getMessage(beforeMessageId), isNotNull);
      expect(await msgRepo.getInboxCursor(groupId), 'gi019-page-2');

      final removalGroupConfig = buildGroupConfigPayload(
        baseGroup.copyWith(lastMembershipEventAt: removedAt),
        <GroupMember>[aliceMember, bobMember],
        configVersionOverride: removedAt,
      );
      await listener.handleReplayEnvelope({
        'groupId': groupId,
        'senderId': alicePeerId,
        'senderUsername': 'Alice',
        'keyEpoch': 0,
        'text': jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': charliePeerId, 'username': 'Charlie'},
          'removedAt': removedAt.toIso8601String(),
          'groupConfig': removalGroupConfig,
        }),
        'timestamp': removedAt.toIso8601String(),
        'messageId': 'gi019-remove-charlie',
      }, rethrowOnError: true);

      expect(await groupRepo.getGroup(groupId), isNull);
      expect(
        await msgRepo.getLatestRemovalTimestampForSender(
          groupId,
          charliePeerId,
        ),
        removedAt,
      );

      await groupRepo.saveGroup(
        baseGroup.copyWith(lastMembershipEventAt: readdAt),
      );
      for (final groupMember in <GroupMember>[
        aliceMember,
        bobMember,
        readdedCharlieMember,
      ]) {
        await groupRepo.saveMember(groupMember);
      }
      await groupRepo.saveKey(keyEpoch1);
      await groupRepo.saveKey(keyEpoch2);
      bridge.addPage(groupId, 'gi019-page-2', [
        removedWindowReplay,
      ], 'gi019-page-3');
      bridge.addPage(groupId, 'gi019-page-3', [
        postReaddReplay,
        removedWindowReplay,
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
        pendingKeyRepairRepo: pendingRepo,
        requestGroupKeyRepair: repairRequests.add,
        selfPeerId: charliePeerId,
      );

      final messages = await msgRepo.getMessagesPage(groupId);
      expect(
        messages.where((message) => message.id == beforeMessageId),
        hasLength(1),
      );
      expect(
        messages.singleWhere((message) => message.id == beforeMessageId).text,
        beforeText,
      );
      expect(
        messages.where((message) => message.id == removedWindowMessageId),
        isEmpty,
      );
      expect(
        messages.where((message) => message.text == removedWindowText),
        isEmpty,
      );
      expect(
        messages.where((message) => message.id == postReaddMessageId),
        hasLength(1),
      );
      expect(
        messages
            .singleWhere((message) => message.id == postReaddMessageId)
            .text,
        postReaddText,
      );
      expect(await msgRepo.getInboxCursor(groupId), '');
      expect(
        pendingRepo.repairs.values.where(
          (repair) => repair.messageId == removedWindowMessageId,
        ),
        isEmpty,
      );
      expect(
        repairRequests.where(
          (request) => request.messageId == removedWindowMessageId,
        ),
        isEmpty,
      );
      expect(
        flowEvents.where(
          (event) =>
              event['event'] ==
              'GROUP_HANDLE_INCOMING_MSG_SELF_REMOVED_WINDOW_AFTER_REJOIN',
        ),
        hasLength(greaterThanOrEqualTo(1)),
      );

      final cursorCommands = bridge.sentMessages
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .where((message) => message['cmd'] == 'group:inboxRetrieveCursor')
          .map(
            (message) =>
                (message['payload'] as Map<String, dynamic>)['cursor']
                    as String? ??
                '',
          )
          .toList(growable: false);
      expect(cursorCommands, <String>['', 'gi019-page-2', 'gi019-page-3']);
    },
  );

  test(
    'GI-021 inbox replay rejects non-member sender without rendering',
    () async {
      const groupId = 'group-1';
      const nonMemberPeerId = 'peer-non-member';
      const messageId = 'gi021-non-member-replay';
      const messageText = 'GI-021 non-member replay must not render';
      final messageAt = DateTime.utc(2026, 5, 12, 15);
      final flowEvents = <Map<String, dynamic>>[];

      debugSetFlowEventSink((payload) {
        flowEvents.add(Map<String, dynamic>.from(payload));
      });
      addTearDown(() {
        debugSetFlowEventSink(null);
      });

      await saveDefaultReplayKey();
      expect(await groupRepo.getMember(groupId, nonMemberPeerId), isNull);

      final replayEnvelope = await buildGroupOfflineReplayEnvelope(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: jsonEncode({
          'groupId': groupId,
          'senderId': nonMemberPeerId,
          'senderUsername': 'Non Member',
          'keyEpoch': 1,
          'text': messageText,
          'timestamp': messageAt.toIso8601String(),
          'messageId': messageId,
        }),
        messageId: messageId,
        senderPeerId: nonMemberPeerId,
        senderPublicKey: 'pk-$nonMemberPeerId',
        senderPrivateKey: 'sk-$nonMemberPeerId',
        keyInfo: GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'replay-key-1',
          createdAt: DateTime.utc(2026, 5, 12, 14),
        ),
      );
      bridge.addPage(groupId, '', [
        {
          'from': nonMemberPeerId,
          'message': replayEnvelope,
          'timestamp': messageAt.millisecondsSinceEpoch,
        },
      ], '');
      bridge.commandLog.clear();
      bridge.sentMessages.clear();

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      final messages = await msgRepo.getMessagesPage(groupId);
      expect(await msgRepo.getMessage(messageId), isNull);
      expect(messages.where((message) => message.id == messageId), isEmpty);
      expect(messages.where((message) => message.text == messageText), isEmpty);
      expect(bridge.commandLog, contains('group:inboxRetrieveCursor'));
      expect(bridge.commandLog, isNot(contains('payload.verify')));
      expect(bridge.commandLog, isNot(contains('group.decrypt')));
      expect(
        flowEvents,
        contains(
          isA<Map<String, dynamic>>()
              .having(
                (event) => event['event'],
                'event',
                'GROUP_DRAIN_OFFLINE_INBOX_REPLAY_SIGNATURE_REJECTED',
              )
              .having(
                (event) => (event['details'] as Map<String, dynamic>)['error'],
                'error',
                'unknown_sender',
              ),
        ),
      );
    },
  );

  test(
    'GI-022 revoked-device replay is rejected while active-device replay continues',
    () async {
      const groupId = 'group-1';
      const senderPeerId = 'peer-sender';
      const activeDeviceId = 'device-active';
      const activeTransportPeerId = 'transport-active';
      const revokedDeviceId = 'device-revoked';
      const revokedTransportPeerId = 'transport-revoked';
      const revokedMessageId = 'gi022-revoked-device-replay';
      const activeMessageId = 'gi022-active-device-replay';
      const revokedText = 'GI-022 revoked device must not render';
      const activeText = 'GI-022 active device still renders';
      final groupCreatedAt = DateTime.utc(2026, 5, 12, 14);
      final revokedAt = groupCreatedAt.add(const Duration(minutes: 10));
      final revokedMessageAt = groupCreatedAt.add(const Duration(minutes: 20));
      final activeMessageAt = groupCreatedAt.add(const Duration(minutes: 21));
      final flowEvents = <Map<String, dynamic>>[];

      debugSetFlowEventSink((payload) {
        flowEvents.add(Map<String, dynamic>.from(payload));
      });
      addTearDown(() {
        debugSetFlowEventSink(null);
      });

      await groupRepo.updateGroup(
        testGroup.copyWith(createdAt: groupCreatedAt),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: senderPeerId,
          username: 'Sender',
          role: MemberRole.writer,
          publicKey: 'pk-active-device',
          devices: [
            GroupMemberDeviceIdentity(
              deviceId: activeDeviceId,
              transportPeerId: activeTransportPeerId,
              deviceSigningPublicKey: 'pk-active-device',
              mlKemPublicKey: 'mlkem-active-device',
              keyPackageId: 'key-package-active-device',
              keyPackagePublicMaterial: 'key-package-public-active-device',
            ),
            GroupMemberDeviceIdentity(
              deviceId: revokedDeviceId,
              transportPeerId: revokedTransportPeerId,
              deviceSigningPublicKey: 'pk-revoked-device',
              mlKemPublicKey: 'mlkem-revoked-device',
              keyPackageId: 'key-package-revoked-device',
              keyPackagePublicMaterial: 'key-package-public-revoked-device',
              status: GroupMemberDeviceStatus.revoked,
              revokedAt: revokedAt,
            ),
          ],
          joinedAt: groupCreatedAt,
        ),
      );
      await saveDefaultReplayKey();

      Future<Map<String, dynamic>> replayFromDevice({
        required String messageId,
        required String text,
        required DateTime timestamp,
        required String deviceId,
        required String transportPeerId,
        required String publicKey,
        required String privateKey,
      }) async {
        final replayEnvelope = await buildGroupOfflineReplayEnvelope(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintext: jsonEncode({
            'groupId': groupId,
            'senderId': senderPeerId,
            'senderUsername': 'Sender',
            'senderDeviceId': deviceId,
            'transportPeerId': transportPeerId,
            'keyEpoch': 1,
            'text': text,
            'timestamp': timestamp.toIso8601String(),
            'messageId': messageId,
          }),
          messageId: messageId,
          senderPeerId: senderPeerId,
          senderPublicKey: publicKey,
          senderPrivateKey: privateKey,
          senderDeviceId: deviceId,
          senderTransportPeerId: transportPeerId,
          keyInfo: GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'replay-key-1',
            createdAt: groupCreatedAt,
          ),
        );
        return {
          'from': transportPeerId,
          'message': replayEnvelope,
          'timestamp': timestamp.millisecondsSinceEpoch,
        };
      }

      final revokedReplay = await replayFromDevice(
        messageId: revokedMessageId,
        text: revokedText,
        timestamp: revokedMessageAt,
        deviceId: revokedDeviceId,
        transportPeerId: revokedTransportPeerId,
        publicKey: 'pk-revoked-device',
        privateKey: 'sk-revoked-device',
      );
      final activeReplay = await replayFromDevice(
        messageId: activeMessageId,
        text: activeText,
        timestamp: activeMessageAt,
        deviceId: activeDeviceId,
        transportPeerId: activeTransportPeerId,
        publicKey: 'pk-active-device',
        privateKey: 'sk-active-device',
      );

      bridge.addPage(groupId, '', [revokedReplay, activeReplay], '');
      bridge.commandLog.clear();
      bridge.sentMessages.clear();

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      expect(await msgRepo.getMessage(revokedMessageId), isNull);
      final activeMessage = await msgRepo.getMessage(activeMessageId);
      expect(activeMessage, isNotNull);
      expect(activeMessage!.text, activeText);
      expect(activeMessage.senderPeerId, senderPeerId);
      expect(activeMessage.transportPeerId, activeTransportPeerId);
      expect(activeMessage.keyGeneration, 1);
      expect(activeMessage.status, 'delivered');

      final messages = await msgRepo.getMessagesPage(groupId);
      expect(
        messages.where((message) => message.id == revokedMessageId),
        isEmpty,
      );
      expect(messages.where((message) => message.text == revokedText), isEmpty);
      expect(
        messages.where((message) => message.id == activeMessageId),
        hasLength(1),
      );
      expect(await msgRepo.getInboxCursor(groupId), '');
      final uniqueCommands = bridge.sentMessages
          .toSet()
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .map((message) => message['cmd'] as String?)
          .whereType<String>()
          .toList(growable: false);
      expect(
        uniqueCommands.where((command) => command == 'payload.verify'),
        hasLength(1),
      );
      expect(
        uniqueCommands.where((command) => command == 'group.decrypt'),
        hasLength(1),
      );
      expect(
        flowEvents,
        contains(
          isA<Map<String, dynamic>>()
              .having(
                (event) => event['event'],
                'event',
                'GROUP_DRAIN_OFFLINE_INBOX_REPLAY_SIGNATURE_REJECTED',
              )
              .having(
                (event) => (event['details'] as Map<String, dynamic>)['error'],
                'error',
                'revoked_device',
              ),
        ),
      );
    },
  );

  test(
    'GK-024 late-joining member skips pre-join replay and renders post-join replay',
    () async {
      const groupId = 'group-1';
      const alicePeerId = 'peer-alice';
      const bobPeerId = 'peer-bob';
      const danaPeerId = 'peer-dana';
      const oldKeyPreJoinMessageId = 'gk024-old-key-prejoin';
      const currentKeyPreJoinMessageId = 'gk024-current-key-prejoin';
      const postJoinMessageId = 'gk024-post-join-replay';
      const oldKeyPreJoinText = 'GK-024 old key before Dana joins';
      const currentKeyPreJoinText = 'GK-024 current key before Dana joins';
      const postJoinText = 'GK-024 after Dana joins';
      final groupCreatedAt = DateTime.utc(2026, 5, 12, 14);
      final oldKeyPreJoinAt = groupCreatedAt.add(const Duration(minutes: 1));
      final currentKeyPreJoinAt = groupCreatedAt.add(
        const Duration(minutes: 2),
      );
      final danaJoinedAt = groupCreatedAt.add(const Duration(minutes: 3));
      final postJoinAt = groupCreatedAt.add(const Duration(minutes: 4));
      final oldKeyInfo = GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'gk024-key-epoch-1',
        createdAt: groupCreatedAt,
      );
      final currentKeyInfo = GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 2,
        encryptedKey: 'gk024-key-epoch-2',
        createdAt: danaJoinedAt,
      );

      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink((payload) {
        flowEvents.add(Map<String, dynamic>.from(payload));
      });
      addTearDown(() {
        debugSetFlowEventSink(null);
      });

      GroupMember member({
        required String peerId,
        required String username,
        required MemberRole role,
        required DateTime joinedAt,
      }) {
        return GroupMember(
          groupId: groupId,
          peerId: peerId,
          username: username,
          role: role,
          publicKey: 'pk-$peerId',
          mlKemPublicKey: 'mlkem-$peerId',
          joinedAt: joinedAt,
        );
      }

      await groupRepo.updateGroup(
        testGroup.copyWith(
          name: 'GK-024 Group',
          createdAt: groupCreatedAt,
          createdBy: alicePeerId,
          myRole: GroupRole.member,
        ),
      );
      await groupRepo.removeMember(groupId, 'peer-sender');
      for (final groupMember in <GroupMember>[
        member(
          peerId: alicePeerId,
          username: 'Alice',
          role: MemberRole.admin,
          joinedAt: groupCreatedAt,
        ),
        member(
          peerId: bobPeerId,
          username: 'Bob',
          role: MemberRole.writer,
          joinedAt: groupCreatedAt.add(const Duration(seconds: 1)),
        ),
        member(
          peerId: danaPeerId,
          username: 'Dana',
          role: MemberRole.writer,
          joinedAt: danaJoinedAt,
        ),
      ]) {
        await groupRepo.saveMember(groupMember);
      }
      await groupRepo.saveKey(currentKeyInfo);

      Future<Map<String, dynamic>> replayMessage({
        required String messageId,
        required String text,
        required DateTime timestamp,
        required GroupKeyInfo keyInfo,
      }) async {
        final replayEnvelope = await buildGroupOfflineReplayEnvelope(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: groupId,
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintext: jsonEncode({
            'groupId': groupId,
            'senderId': alicePeerId,
            'senderUsername': 'Alice',
            'keyEpoch': keyInfo.keyGeneration,
            'text': text,
            'timestamp': timestamp.toIso8601String(),
            'messageId': messageId,
          }),
          messageId: messageId,
          senderPeerId: alicePeerId,
          senderPublicKey: 'pk-$alicePeerId',
          senderPrivateKey: 'sk-$alicePeerId',
          keyInfo: keyInfo,
          recipientPeerIds: const <String>[danaPeerId],
        );
        return <String, dynamic>{
          'from': alicePeerId,
          'message': replayEnvelope,
          'timestamp': timestamp.millisecondsSinceEpoch,
        };
      }

      final oldKeyPreJoinReplay = await replayMessage(
        messageId: oldKeyPreJoinMessageId,
        text: oldKeyPreJoinText,
        timestamp: oldKeyPreJoinAt,
        keyInfo: oldKeyInfo,
      );
      final currentKeyPreJoinReplay = await replayMessage(
        messageId: currentKeyPreJoinMessageId,
        text: currentKeyPreJoinText,
        timestamp: currentKeyPreJoinAt,
        keyInfo: currentKeyInfo,
      );
      final postJoinReplay = await replayMessage(
        messageId: postJoinMessageId,
        text: postJoinText,
        timestamp: postJoinAt,
        keyInfo: currentKeyInfo,
      );
      final pendingRepo = _InMemoryGroupPendingKeyRepairRepository();
      final repairRequests = <GroupKeyRepairRequest>[];

      bridge.addPage(groupId, '', [
        oldKeyPreJoinReplay,
        currentKeyPreJoinReplay,
        postJoinReplay,
      ], '');
      bridge.commandLog.clear();
      bridge.sentMessages.clear();

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        pendingKeyRepairRepo: pendingRepo,
        requestGroupKeyRepair: repairRequests.add,
        selfPeerId: danaPeerId,
      );

      final messages = await msgRepo.getMessagesPage(groupId);
      expect(await msgRepo.getMessage(oldKeyPreJoinMessageId), isNull);
      expect(await msgRepo.getMessage(currentKeyPreJoinMessageId), isNull);
      expect(
        messages.where((message) => message.text == oldKeyPreJoinText),
        isEmpty,
      );
      expect(
        messages.where((message) => message.text == currentKeyPreJoinText),
        isEmpty,
      );
      expect(
        messages.where((message) => message.id == postJoinMessageId),
        hasLength(1),
      );
      expect(
        messages.singleWhere((message) => message.id == postJoinMessageId).text,
        postJoinText,
      );
      expect(messages, hasLength(1));
      expect(await msgRepo.getInboxCursor(groupId), '');
      expect(
        pendingRepo.repairs.values.where(
          (repair) =>
              repair.messageId == oldKeyPreJoinMessageId ||
              repair.messageId == currentKeyPreJoinMessageId,
        ),
        isEmpty,
      );
      expect(
        repairRequests.where(
          (request) =>
              request.messageId == oldKeyPreJoinMessageId ||
              request.messageId == currentKeyPreJoinMessageId,
        ),
        isEmpty,
      );
      expect(
        flowEvents.where(
          (event) =>
              event['event'] ==
              'GROUP_DRAIN_OFFLINE_INBOX_PRE_JOIN_REPLAY_SKIPPED',
        ),
        hasLength(2),
      );
      expect(
        flowEvents.where(
          (event) =>
              event['event'] == 'GROUP_DRAIN_OFFLINE_INBOX_DECODE_SKIPPED',
        ),
        isEmpty,
      );
      expect(
        flowEvents.where(
          (event) => event['event'] == 'GROUP_FL_BRIDGE_DECRYPT_REQUEST',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'PREREQ-REMOTE-EVENT-FAMILIES offline replay applies trusted-private tombstones idempotently',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          joinedAt: DateTime.utc(2026, 5, 1, 11, 55),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-target',
          username: 'Target',
          role: MemberRole.writer,
          joinedAt: DateTime.utc(2026, 5, 1, 11, 56),
        ),
      );

      final messageAt = DateTime.utc(2026, 5, 1, 12);
      await msgRepo.saveMessage(
        GroupMessage(
          id: 'offline-delete-target',
          groupId: 'group-1',
          senderPeerId: 'peer-target',
          senderUsername: 'Target',
          text: 'Offline target',
          timestamp: messageAt,
          createdAt: messageAt,
        ),
      );

      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
      );
      addTearDown(listener.dispose);

      final deletedAt = messageAt.add(const Duration(minutes: 1));
      final bannedAt = messageAt.add(const Duration(minutes: 2));
      final unbannedAt = messageAt.add(const Duration(minutes: 3));
      final staleBanAt = messageAt.add(const Duration(minutes: 2, seconds: 30));

      Map<String, dynamic> replayEnvelope({
        required String id,
        required Map<String, dynamic> systemPayload,
        required DateTime timestamp,
      }) {
        return {
          'message': jsonEncode({
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode(systemPayload),
            'timestamp': timestamp.toIso8601String(),
            'messageId': id,
          }),
        };
      }

      final deleteEnvelope = replayEnvelope(
        id: 'offline-delete-event',
        timestamp: deletedAt,
        systemPayload: {
          '__sys': 'group_message_deleted',
          'targetMessageId': 'offline-delete-target',
          'deletedAt': deletedAt.toIso8601String(),
        },
      );
      final banEnvelope = replayEnvelope(
        id: 'offline-ban-event',
        timestamp: bannedAt,
        systemPayload: {
          '__sys': 'member_banned',
          'targetPeerId': 'peer-target',
          'targetUsername': 'Target',
          'bannedAt': bannedAt.toIso8601String(),
        },
      );
      final unbanEnvelope = replayEnvelope(
        id: 'offline-unban-event',
        timestamp: unbannedAt,
        systemPayload: {
          '__sys': 'member_unbanned',
          'targetPeerId': 'peer-target',
          'targetUsername': 'Target',
          'unbannedAt': unbannedAt.toIso8601String(),
        },
      );
      final staleBanEnvelope = replayEnvelope(
        id: 'offline-stale-ban-after-unban',
        timestamp: staleBanAt,
        systemPayload: {
          '__sys': 'member_banned',
          'targetPeerId': 'peer-target',
          'targetUsername': 'Target',
          'bannedAt': staleBanAt.toIso8601String(),
        },
      );

      bridge.addPage('group-1', '', [
        deleteEnvelope,
        deleteEnvelope,
        banEnvelope,
        banEnvelope,
        unbanEnvelope,
        unbanEnvelope,
        staleBanEnvelope,
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
      );

      expect(await msgRepo.getMessage('offline-delete-target'), isNull);
      expect(await groupRepo.getMember('group-1', 'peer-target'), isNull);

      final messages = await msgRepo.getMessagesPage('group-1', limit: 20);
      expect(
        messages.where(
          (message) => message.id.startsWith(
            'sys-group_message_deleted:group-1:offline-delete-target:',
          ),
        ),
        hasLength(1),
      );
      expect(
        messages.where(
          (message) =>
              message.id.startsWith('sys-member_banned:group-1:peer-target:'),
        ),
        hasLength(1),
      );
      expect(
        messages.where(
          (message) =>
              message.id.startsWith('sys-member_unbanned:group-1:peer-target:'),
        ),
        hasLength(1),
      );
      expect(msgRepo.count, 3);
    },
  );

  test(
    'within-window backlog is retained and records the retained timestamp',
    () async {
      final retainedAt = groupBacklogRetentionCutoff(
        DateTime.now().toUtc(),
      ).add(const Duration(hours: 1));

      bridge.addPage('group-1', '', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Retained backlog',
          'timestamp': retainedAt.toIso8601String(),
          'messageId': 'msg-retained-backlog',
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      final messages = await msgRepo.getMessagesPage('group-1');
      final group = await groupRepo.getGroup('group-1');

      expect(messages, hasLength(1));
      expect(messages.single.id, 'msg-retained-backlog');
      expect(group, isNotNull);
      expect(group!.lastBacklogExpiredAt, isNull);
      expect(group.lastBacklogRetainedAt, retainedAt);
    },
  );

  test(
    'beyond-window backlog is skipped and records the expired timestamp',
    () async {
      final expiredAt = groupBacklogRetentionCutoff(
        DateTime.now().toUtc(),
      ).subtract(const Duration(hours: 1));

      bridge.addPage('group-1', '', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Expired backlog',
          'timestamp': expiredAt.toIso8601String(),
          'messageId': 'msg-expired-backlog',
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      final group = await groupRepo.getGroup('group-1');

      expect(await msgRepo.getMessagesPage('group-1'), isEmpty);
      expect(group, isNotNull);
      expect(group!.lastBacklogExpiredAt, expiredAt);
      expect(group.lastBacklogRetainedAt, isNull);
    },
  );

  test(
    'mixed old and new cursor pages keep retained backlog and record both boundaries',
    () async {
      final cutoff = groupBacklogRetentionCutoff(DateTime.now().toUtc());
      final expiredAt = cutoff.subtract(const Duration(hours: 1));
      final retainedAt = cutoff.add(const Duration(hours: 1));

      bridge.addPage('group-1', '', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Expired page',
          'timestamp': expiredAt.toIso8601String(),
          'messageId': 'msg-expired-page',
        },
      ], 'cursor-retained');

      bridge.addPage('group-1', 'cursor-retained', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Retained page',
          'timestamp': retainedAt.toIso8601String(),
          'messageId': 'msg-retained-page',
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      final messages = await msgRepo.getMessagesPage('group-1');
      final group = await groupRepo.getGroup('group-1');
      final retrieveCount = bridge.commandLog
          .where((command) => command == 'group:inboxRetrieveCursor')
          .length;

      expect(messages, hasLength(1));
      expect(messages.single.id, 'msg-retained-page');
      expect(group, isNotNull);
      expect(group!.lastBacklogExpiredAt, expiredAt);
      expect(group.lastBacklogRetainedAt, retainedAt);
      expect(
        retrieveCount,
        2,
        reason:
            'Expired cursor pages must not stop continuation when later retained backlog still exists',
      );
    },
  );

  test('repeated drains do not resurrect expired backlog', () async {
    final cutoff = groupBacklogRetentionCutoff(DateTime.now().toUtc());
    final expiredAt = cutoff.subtract(const Duration(hours: 1));
    final retainedAt = cutoff.add(const Duration(hours: 1));

    bridge.addPage('group-1', '', [
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Expired replay',
        'timestamp': expiredAt.toIso8601String(),
        'messageId': 'msg-expired-replay',
      },
    ], 'cursor-retained');

    bridge.addPage('group-1', 'cursor-retained', [
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Retained replay',
        'timestamp': retainedAt.toIso8601String(),
        'messageId': 'msg-retained-replay',
      },
    ], '');

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );
    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );

    final messages = await msgRepo.getMessagesPage('group-1');
    final group = await groupRepo.getGroup('group-1');

    expect(messages, hasLength(1));
    expect(messages.single.id, 'msg-retained-replay');
    expect(
      messages.where((message) => message.id == 'msg-expired-replay'),
      isEmpty,
    );
    expect(group, isNotNull);
    expect(group!.lastBacklogExpiredAt, expiredAt);
    expect(group.lastBacklogRetainedAt, retainedAt);
  });

  test(
    'system envelopes older than the retention cutoff still converge membership',
    () async {
      final initialJoinedAt = groupBacklogRetentionCutoff(
        DateTime.now().toUtc(),
      ).subtract(const Duration(days: 2));
      final removedAt = initialJoinedAt.add(const Duration(days: 1));

      await groupRepo.updateGroup(
        testGroup.copyWith(createdAt: initialJoinedAt),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-sender',
          username: 'Sender',
          role: MemberRole.writer,
          joinedAt: initialJoinedAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-self',
          username: 'Self',
          role: MemberRole.writer,
          joinedAt: initialJoinedAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          joinedAt: initialJoinedAt,
        ),
      );

      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
      );
      addTearDown(listener.dispose);

      bridge.addPage('group-1', '', [
        {
          'message': jsonEncode({
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({
              '__sys': 'member_removed',
              'member': {'peerId': 'peer-sender', 'username': 'Sender'},
              'removedAt': removedAt.toIso8601String(),
              'groupConfig': {
                'name': 'Test Group',
                'groupType': 'chat',
                'members': [
                  {'peerId': 'peer-admin', 'role': 'admin'},
                  {'peerId': 'peer-self', 'role': 'writer'},
                ],
                'createdBy': 'peer-admin',
                'createdAt': removedAt.toIso8601String(),
              },
            }),
            'timestamp': removedAt.toIso8601String(),
            'messageId': 'msg-old-member-removed',
          }),
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
      );

      final group = await groupRepo.getGroup('group-1');
      final messages = await msgRepo.getMessagesPage('group-1');

      expect(await groupRepo.getMember('group-1', 'peer-sender'), isNull);
      expect(
        messages.where(
          (message) =>
              message.id.startsWith('sys-member_removed:group-1:peer-sender:'),
        ),
        hasLength(1),
      );
      expect(group, isNotNull);
      expect(group!.lastBacklogExpiredAt, isNull);
      expect(group.lastBacklogRetainedAt, isNull);
    },
  );

  test('drain preserves quotedMessageId from inbox payload', () async {
    final ts = DateTime.now().toUtc().toIso8601String();

    bridge.addPage('group-1', '', [
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Quoted offline reply',
        'timestamp': ts,
        'messageId': 'msg-quoted-offline',
        'quotedMessageId': 'msg-parent-1',
      },
    ], '');

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );

    final messages = await msgRepo.getMessagesPage('group-1');
    expect(messages, hasLength(1));
    expect(messages.first.id, 'msg-quoted-offline');
    expect(messages.first.quotedMessageId, 'msg-parent-1');
  });

  test(
    'GP-026 GMAR-004 duplicate live plus inbox replay enriches video and voice media once',
    () async {
      final mediaRepo = InMemoryMediaAttachmentRepository();
      final ts = DateTime.now().toUtc().toIso8601String();
      await saveDefaultReplayKey();

      await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 1,
        text: '',
        timestamp: ts,
        messageId: 'msg-repair-1',
        mediaAttachmentRepo: mediaRepo,
      );

      final plaintext = jsonEncode({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': '',
        'timestamp': ts,
        'messageId': 'msg-repair-1',
        'quotedMessageId': 'msg-parent-1',
        'media': [
          {
            'id': 'blob-repair-video',
            'mime': 'video/mp4',
            'size': 1024,
            'mediaType': 'video',
            'durationMs': 12000,
            'downloadStatus': 'pending',
            'contentHash': _validContentHash,
            'encryptionKeyBase64': 'key-fixture',
            'encryptionNonce': 'nonce-fixture',
            'encryptionScheme': 'blob_aes_256_gcm_v1',
            'createdAt': ts,
          },
          {
            'id': 'blob-repair-voice',
            'mime': 'audio/mp4',
            'size': 2048,
            'mediaType': 'audio',
            'durationMs': 4200,
            'waveform': [0.2, 0.55, 0.35, 0.8],
            'downloadStatus': 'pending',
            'contentHash': _validContentHash,
            'encryptionKeyBase64': 'key-fixture',
            'encryptionNonce': 'nonce-fixture',
            'encryptionScheme': 'blob_aes_256_gcm_v1',
            'createdAt': ts,
          },
          {
            'id': 'blob-repair-video',
            'mime': 'video/mp4',
            'size': 1024,
            'mediaType': 'video',
            'durationMs': 12000,
            'downloadStatus': 'pending',
            'contentHash': _validContentHash,
            'encryptionKeyBase64': 'key-fixture',
            'encryptionNonce': 'nonce-fixture',
            'encryptionScheme': 'blob_aes_256_gcm_v1',
            'createdAt': ts,
          },
        ],
      });
      final replayEnvelope = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: plaintext,
        messageId: 'msg-repair-1',
      );

      bridge.addPage('group-1', '', [
        {'from': 'peer-sender', 'message': replayEnvelope, 'timestamp': 123},
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        mediaAttachmentRepo: mediaRepo,
      );

      final saved = await msgRepo.getMessage('msg-repair-1');
      expect(saved, isNotNull);
      expect(saved!.quotedMessageId, 'msg-parent-1');
      expect(msgRepo.count, 1);

      final attachments = await mediaRepo.getAttachmentsForMessage(
        'msg-repair-1',
      );
      expect(attachments, hasLength(2));
      final byId = {
        for (final attachment in attachments) attachment.id: attachment,
      };
      expect(
        byId.keys,
        containsAll(['blob-repair-video', 'blob-repair-voice']),
      );
      expect(byId['blob-repair-video']!.mediaType, 'video');
      expect(byId['blob-repair-video']!.durationMs, 12000);
      expect(byId['blob-repair-video']!.contentHash, _validContentHash);
      expect(byId['blob-repair-video']!.encryptionKeyBase64, 'key-fixture');
      expect(byId['blob-repair-video']!.encryptionNonce, 'nonce-fixture');
      expect(
        byId['blob-repair-video']!.encryptionScheme,
        'blob_aes_256_gcm_v1',
      );
      expect(byId['blob-repair-voice']!.mediaType, 'audio');
      expect(byId['blob-repair-voice']!.durationMs, 4200);
      expect(byId['blob-repair-voice']!.waveform, [0.2, 0.55, 0.35, 0.8]);
      expect(byId['blob-repair-voice']!.contentHash, _validContentHash);
      expect(byId['blob-repair-voice']!.encryptionKeyBase64, 'key-fixture');
      expect(byId['blob-repair-voice']!.encryptionNonce, 'nonce-fixture');
      expect(
        byId['blob-repair-voice']!.encryptionScheme,
        'blob_aes_256_gcm_v1',
      );

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(msgRepo.count, 1);
      expect(
        await mediaRepo.getAttachmentsForMessage('msg-repair-1'),
        hasLength(2),
      );
    },
  );

  test(
    'resume drains missed announcement messages exactly once for offline readers',
    () async {
      // Create an announcement group where the local user is a reader.
      final announcementGroup = GroupModel(
        id: 'group-announce',
        name: 'Announcements',
        type: GroupType.announcement,
        topicName: '/mknoon/group/group-announce',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'peer-admin',
        myRole: GroupRole.member,
      );
      await groupRepo.saveGroup(announcementGroup);
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-announce',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final ts = DateTime.now().toUtc().toIso8601String();

      bridge.addPage('group-announce', '', [
        {
          'groupId': 'group-announce',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 1,
          'text': 'Announcement 1',
          'timestamp': ts,
          'messageId': 'msg-ann-1',
        },
        {
          'groupId': 'group-announce',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 1,
          'text': 'Announcement 2',
          'timestamp': ts,
          'messageId': 'msg-ann-2',
        },
      ], '');

      // Also set up group-1 to have no messages (empty page).
      bridge.addPage('group-1', '', [], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      // Both announcement messages should be saved.
      final announceMsgs = await msgRepo.getMessagesPage('group-announce');
      expect(announceMsgs.length, 2);

      // Drain again — should not duplicate.
      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );
      final announceMsgs2 = await msgRepo.getMessagesPage('group-announce');
      expect(announceMsgs2.length, 2);
    },
  );

  test(
    'resume drains first group-inbox page before background continuation completes',
    () async {
      final ts = DateTime.now().toUtc().toIso8601String();

      // Page 1 (first page, returns cursor for page 2).
      bridge.addPage('group-1', '', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Page 1 msg 1',
          'timestamp': ts,
          'messageId': 'msg-p1-1',
        },
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Page 1 msg 2',
          'timestamp': ts,
          'messageId': 'msg-p1-2',
        },
      ], 'cursor-page-2');

      // Page 2 (continuation, no more pages).
      bridge.addPage('group-1', 'cursor-page-2', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Page 2 msg 1',
          'timestamp': ts,
          'messageId': 'msg-p2-1',
        },
      ], '');

      // Drain first page only.
      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        drainAllPages: false,
      );

      // Only first page messages should be saved.
      expect(msgRepo.count, 2);
      final saved = await msgRepo.getMessagesPage('group-1');
      final texts = saved.map((m) => m.text).toSet();
      expect(texts, contains('Page 1 msg 1'));
      expect(texts, contains('Page 1 msg 2'));
      expect(texts, isNot(contains('Page 2 msg 1')));
    },
  );

  test(
    'group inbox continuation uses cursor rather than timestamp guessing',
    () async {
      final ts = DateTime.now().toUtc().toIso8601String();

      // Three pages with cursors.
      bridge.addPage('group-1', '', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Cursor page 1',
          'timestamp': ts,
          'messageId': 'msg-c1',
        },
      ], 'cursor-2');

      bridge.addPage('group-1', 'cursor-2', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Cursor page 2',
          'timestamp': ts,
          'messageId': 'msg-c2',
        },
      ], 'cursor-3');

      bridge.addPage('group-1', 'cursor-3', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Cursor page 3',
          'timestamp': ts,
          'messageId': 'msg-c3',
        },
      ], '');

      // Drain all pages.
      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        drainAllPages: true,
      );

      expect(msgRepo.count, 3);

      // Verify the bridge received cursor-based requests (not timestamp-based).
      final retrieveCmds = bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:inboxRetrieveCursor')
          .toList();

      expect(retrieveCmds.length, 3);

      // First request should have empty cursor.
      expect(retrieveCmds[0]['payload']['cursor'], '');
      // Second request should use cursor-2.
      expect(retrieveCmds[1]['payload']['cursor'], 'cursor-2');
      // Third request should use cursor-3.
      expect(retrieveCmds[2]['payload']['cursor'], 'cursor-3');
    },
  );

  test('stale group inbox cursor stops instead of looping forever', () async {
    bridge.addPage('group-1', '', const [], 'repeat-cursor');
    bridge.addPage('group-1', 'repeat-cursor', const [], 'repeat-cursor');

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );

    final retrieveCmds = bridge.sentMessages
        .map((m) => jsonDecode(m) as Map<String, dynamic>)
        .where((m) => m['cmd'] == 'group:inboxRetrieveCursor')
        .toList();

    expect(retrieveCmds, hasLength(2));
    expect(retrieveCmds[0]['payload']['cursor'], '');
    expect(retrieveCmds[1]['payload']['cursor'], 'repeat-cursor');
    expect(await msgRepo.getInboxCursor('group-1'), 'repeat-cursor');
  });

  test(
    'cursor timeout logs a group error instead of treating backlog as drained',
    () async {
      final output = <String>[];
      final originalDebugPrint = debugPrint;
      flowEventLoggingEnabled = true;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) output.add(message);
      };
      addTearDown(() {
        debugPrint = originalDebugPrint;
        flowEventLoggingEnabled = kDebugMode;
      });

      final timeoutBridge = _TimeoutCursorInboxBridge();
      configureLegacyReplaySigning(timeoutBridge);
      bridge = timeoutBridge;
      timeoutBridge.addTimeout('group-1', '');

      final testGroup2 = GroupModel(
        id: 'group-2',
        name: 'Second Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/group-2',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'peer-admin',
        myRole: GroupRole.member,
      );
      await groupRepo.saveGroup(testGroup2);
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-2',
          peerId: 'peer-sender',
          username: 'Sender',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final ts = DateTime.now().toUtc().toIso8601String();
      timeoutBridge.addPage('group-2', '', [
        {
          'groupId': 'group-2',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Recovered after timeout',
          'timestamp': ts,
          'messageId': 'msg-group-2',
        },
      ], '');

      await drainGroupOfflineInbox(
        bridge: timeoutBridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      final group1Messages = await msgRepo.getMessagesPage('group-1');
      final group2Messages = await msgRepo.getMessagesPage('group-2');
      final events = output
          .where((line) => line.startsWith('[FLOW] '))
          .map(
            (line) =>
                jsonDecode(line.substring('[FLOW] '.length))
                    as Map<String, dynamic>,
          )
          .toList();

      expect(group1Messages, isEmpty);
      expect(group2Messages, hasLength(1));
      expect(group2Messages.single.id, 'msg-group-2');
      expect(
        events.any(
          (event) =>
              event['event'] == 'GROUP_DRAIN_OFFLINE_INBOX_GROUP_ERROR' &&
              (event['details'] as Map<String, dynamic>)['groupId'] ==
                  'group-1',
        ),
        isTrue,
      );
      final groupError = events.firstWhere(
        (event) => event['event'] == 'GROUP_DRAIN_OFFLINE_INBOX_GROUP_ERROR',
      );
      expect(
        groupError['details']['error'],
        contains('Simulated cursor timeout'),
      );
      final errorTiming = events.firstWhere(
        (event) =>
            event['event'] == 'GROUP_DRAIN_OFFLINE_INBOX_TIMING' &&
            (event['details'] as Map<String, dynamic>)['scope'] == 'group' &&
            (event['details'] as Map<String, dynamic>)['outcome'] == 'error',
      );
      expect(errorTiming['details']['groupId'], 'group-1');
      expect(errorTiming['details']['elapsedMs'], isA<int>());
      expect(
        events.any(
          (event) =>
              event['event'] == 'GROUP_DRAIN_OFFLINE_INBOX_GROUP_DONE' &&
              (event['details'] as Map<String, dynamic>)['groupId'] ==
                  'group-1',
        ),
        isFalse,
      );
    },
  );

  test(
    'GO-008 cursor error flow logs redact JSON payload plaintext and keys',
    () async {
      const protectedText = 'GO-008 offline plaintext must not hit logs';
      const rawCiphertext = 'GO-008 offline ciphertext must not hit logs';
      const rawNonce = 'GO-008 offline nonce must not hit logs';
      const rawGroupKey = 'GO-008 offline group key must not hit logs';
      const mediaKey = 'GO-008 offline media key must not hit logs';
      final sensitiveBridge = _SensitiveCursorErrorBridge(
        'relay failed {"text":"$protectedText","ciphertext":"$rawCiphertext","nonce":"$rawNonce","groupKey":"$rawGroupKey","encryptionKeyBase64":"$mediaKey"} /ip4/10.0.0.1/tcp/4001/p2p/12D3KooWRelayPeer',
      );
      configureLegacyReplaySigning(sensitiveBridge);
      bridge = sensitiveBridge;

      final output = <String>[];
      final previousLogging = flowEventLoggingEnabled;
      final originalDebugPrint = debugPrint;
      flowEventLoggingEnabled = true;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) output.add(message);
      };
      addTearDown(() {
        debugPrint = originalDebugPrint;
        flowEventLoggingEnabled = previousLogging;
      });

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      expect(await msgRepo.getMessagesPage('group-1'), isEmpty);
      final events = output
          .where((line) => line.startsWith('[FLOW] '))
          .map(
            (line) =>
                jsonDecode(line.substring('[FLOW] '.length))
                    as Map<String, dynamic>,
          )
          .toList();
      expect(
        events.any(
          (event) => event['event'] == 'GROUP_DRAIN_OFFLINE_INBOX_GROUP_ERROR',
        ),
        isTrue,
      );
      final encodedEvents = jsonEncode(events);
      for (final fragment in [
        protectedText,
        rawCiphertext,
        rawNonce,
        rawGroupKey,
        mediaKey,
        '/ip4/10.0.0.1',
      ]) {
        expect(encodedEvents, isNot(contains(fragment)));
      }
      expect(encodedEvents, contains('[redacted]'));
      expect(encodedEvents, contains('[redacted:multiaddr]'));
    },
  );

  test('emits GROUP_DRAIN_OFFLINE_INBOX_TIMING with batch metadata', () async {
    final testGroup = GroupModel(
      id: 'group-1',
      name: 'Test Group',
      type: GroupType.chat,
      topicName: '/mknoon/group/group-1',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.admin,
    );
    await groupRepo.saveGroup(testGroup);

    final ts = DateTime.now().toUtc().toIso8601String();
    bridge.addPage('group-1', '', [
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Drain timing proof',
        'timestamp': ts,
        'messageId': 'msg-d1',
      },
    ], '');

    final output = <String>[];
    final originalDebugPrint = debugPrint;
    flowEventLoggingEnabled = true;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) output.add(message);
    };
    addTearDown(() {
      debugPrint = originalDebugPrint;
      flowEventLoggingEnabled = kDebugMode;
    });

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      drainAllPages: true,
    );

    final events = output
        .where((line) => line.startsWith('[FLOW] '))
        .map(
          (line) =>
              jsonDecode(line.substring('[FLOW] '.length))
                  as Map<String, dynamic>,
        )
        .toList();

    final begin = events.firstWhere(
      (event) => event['event'] == 'GROUP_DRAIN_OFFLINE_INBOX_BEGIN',
    );
    expect(begin['details'], isEmpty);

    final groupDone = events.firstWhere(
      (event) => event['event'] == 'GROUP_DRAIN_OFFLINE_INBOX_GROUP_DONE',
    );
    expect(groupDone['details']['groupId'], 'group-1');
    expect(groupDone['details']['messageCount'], 1);

    final done = events.firstWhere(
      (event) => event['event'] == 'GROUP_DRAIN_OFFLINE_INBOX_DONE',
    );
    expect(done['details']['groupCount'], 1);

    final timing = events.lastWhere(
      (event) => event['event'] == 'GROUP_DRAIN_OFFLINE_INBOX_TIMING',
    );
    expect(timing['details']['outcome'], 'complete');
    expect(timing['details']['scope'], 'batch');
    expect(timing['details']['groupCount'], 1);
    expect(timing['details']['drainAllPages'], isTrue);
    expect(timing['details']['pageSize'], 50);
    expect(timing['details']['elapsedMs'], isA<int>());
  });

  // ---------------------------------------------------------------------------
  // Existing tests adapted to cursor-based API
  // ---------------------------------------------------------------------------

  test('drains offline inbox and saves messages to repo', () async {
    final ts = DateTime.now().toUtc().toIso8601String();

    bridge.addPage('group-1', '', [
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Offline msg 1',
        'timestamp': ts,
        'messageId': 'msg-off-1',
      },
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Offline msg 2',
        'timestamp': ts,
        'messageId': 'msg-off-2',
      },
    ], '');

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );

    expect(msgRepo.count, 2);
    expect(bridge.commandLog, contains('group:inboxRetrieveCursor'));
  });

  test(
    'replayed group messages emit on the listener stream when provided',
    () async {
      final ts = DateTime.now().toUtc().toIso8601String();
      bridge.addPage('group-1', '', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Replay me into Feed',
          'timestamp': ts,
          'messageId': 'msg-replay-stream-1',
        },
      ], '');

      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );
      final replayedMessages = <GroupMessage>[];
      final subscription = listener.groupMessageStream.listen(
        replayedMessages.add,
      );
      addTearDown(() async {
        await subscription.cancel();
        listener.dispose();
      });

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
      );

      expect(msgRepo.count, 1);
      expect(replayedMessages, hasLength(1));
      expect(replayedMessages.single.id, 'msg-replay-stream-1');
      expect(replayedMessages.single.text, 'Replay me into Feed');
    },
  );

  test('does not crash on empty inbox', () async {
    bridge.addPage('group-1', '', [], '');

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );

    expect(msgRepo.count, 0);
    expect(bridge.commandLog, contains('group:inboxRetrieveCursor'));
  });

  test(
    'per-group error isolation: first group error does not block second',
    () async {
      final testGroup2 = GroupModel(
        id: 'group-2',
        name: 'Second Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/group-2',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'peer-admin',
        myRole: GroupRole.member,
      );
      await groupRepo.saveGroup(testGroup2);
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-2',
          peerId: 'peer-sender',
          username: 'Sender',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final ts = DateTime.now().toUtc().toIso8601String();

      // Group 1: no page registered (will cause error or empty result).
      // Group 2: has messages.
      bridge.addPage('group-2', '', [
        {
          'groupId': 'group-2',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Hello from group 2',
          'timestamp': ts,
          'messageId': 'msg-g2-err',
        },
      ], '');

      // Group 1 returns empty (no page registered for it), so no error,
      // just no messages saved.
      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      // Group 2's message should have been saved.
      expect(msgRepo.count, 1);
    },
  );

  test('drains inbox for archived groups too', () async {
    await groupRepo.archiveGroup('group-1');

    final ts = DateTime.now().toUtc().toIso8601String();

    bridge.addPage('group-1', '', [
      {
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Archived group msg',
        'timestamp': ts,
        'messageId': 'msg-archived',
      },
    ], '');

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
    );

    expect(msgRepo.count, 1);
  });

  // ---------------------------------------------------------------------------
  // Media attachment tests
  // ---------------------------------------------------------------------------
  test('drains inbox message with media — saves media attachments', () async {
    final mediaRepo = InMemoryMediaAttachmentRepository();

    final inboxMessage = jsonEncode({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 1,
      'text': 'Photo message',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'messageId': 'msg-media',
      'media': [
        {
          'id': 'blob-inbox-1',
          'mime': 'image/jpeg',
          'size': 12345,
          'mediaType': 'image',
          'downloadStatus': 'pending',
          'contentHash': _validContentHash,
          'encryptionKeyBase64': 'key-fixture',
          'encryptionNonce': 'nonce-fixture',
          'encryptionScheme': 'blob_aes_256_gcm_v1',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      ],
    });

    // Use raw envelope format (from, message, timestamp)
    bridge.addPage('group-1', '', [
      {'from': 'peer-sender', 'message': inboxMessage, 'timestamp': 123},
    ], '');

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      mediaAttachmentRepo: mediaRepo,
    );

    expect(msgRepo.count, 1);
    expect(mediaRepo.count, 1);
    final pending = await mediaRepo.getPendingDownloads();
    expect(pending.length, 1);
    expect(pending.first.mime, 'image/jpeg');
  });

  test(
    'drains encrypted replay with quote plus image, video, GIF, and voice attachments',
    () async {
      final mediaRepo = InMemoryMediaAttachmentRepository();
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'replay-key-1',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      final plaintext = jsonEncode({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Encrypted mixed media replay',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'messageId': 'msg-encrypted-mixed-media',
        'quotedMessageId': 'msg-parent-1',
        'media': [
          {
            'id': 'blob-image-1',
            'mime': 'image/jpeg',
            'size': 12345,
            'mediaType': 'image',
            'downloadStatus': 'pending',
            'contentHash': _validContentHash,
            'encryptionKeyBase64': 'key-fixture',
            'encryptionNonce': 'nonce-fixture',
            'encryptionScheme': 'blob_aes_256_gcm_v1',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
          {
            'id': 'blob-video-1',
            'mime': 'video/mp4',
            'size': 54321,
            'mediaType': 'video',
            'durationMs': 9876,
            'downloadStatus': 'pending',
            'contentHash': _validContentHash,
            'encryptionKeyBase64': 'key-fixture',
            'encryptionNonce': 'nonce-fixture',
            'encryptionScheme': 'blob_aes_256_gcm_v1',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
          {
            'id': 'blob-gif-1',
            'mime': 'image/gif',
            'size': 4567,
            'mediaType': 'image',
            'downloadStatus': 'pending',
            'contentHash': _validContentHash,
            'encryptionKeyBase64': 'key-fixture',
            'encryptionNonce': 'nonce-fixture',
            'encryptionScheme': 'blob_aes_256_gcm_v1',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
          {
            'id': 'blob-audio-1',
            'mime': 'audio/mp4',
            'size': 6543,
            'mediaType': 'audio',
            'durationMs': 4321,
            'waveform': [0.2, 0.8],
            'downloadStatus': 'pending',
            'contentHash': _validContentHash,
            'encryptionKeyBase64': 'key-fixture',
            'encryptionNonce': 'nonce-fixture',
            'encryptionScheme': 'blob_aes_256_gcm_v1',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        ],
      });

      final replayEnvelope = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: plaintext,
        messageId: 'msg-encrypted-mixed-media',
      );

      bridge.addPage('group-1', '', [
        {'from': 'peer-sender', 'message': replayEnvelope, 'timestamp': 123},
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(bridge.commandLog, contains('group.decrypt'));

      final saved = await msgRepo.getMessage('msg-encrypted-mixed-media');
      expect(saved, isNotNull);
      expect(saved!.quotedMessageId, 'msg-parent-1');

      final attachments = await mediaRepo.getAttachmentsForMessage(saved.id);
      expect(attachments, hasLength(4));

      final byId = {
        for (final attachment in attachments) attachment.id: attachment,
      };
      expect(byId['blob-image-1']!.mime, 'image/jpeg');
      expect(byId['blob-image-1']!.mediaType, 'image');
      expect(byId['blob-video-1']!.mime, 'video/mp4');
      expect(byId['blob-video-1']!.mediaType, 'video');
      expect(byId['blob-gif-1']!.mime, 'image/gif');
      expect(byId['blob-gif-1']!.mediaType, 'image');
      expect(byId['blob-audio-1']!.mime, 'audio/mp4');
      expect(byId['blob-audio-1']!.mediaType, 'audio');
    },
  );

  test(
    'skips encrypted replay with hashless media before message or attachment storage',
    () async {
      final mediaRepo = InMemoryMediaAttachmentRepository();
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'replay-key-1',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      final plaintext = jsonEncode({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Encrypted hashless media replay',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'messageId': 'msg-encrypted-hashless-media',
        'media': [
          {
            'id': 'blob-hashless-replay',
            'mime': 'image/jpeg',
            'size': 8910,
            'mediaType': 'image',
            'downloadStatus': 'pending',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        ],
      });

      final replayEnvelope = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: plaintext,
        messageId: 'msg-encrypted-hashless-media',
      );

      bridge.addPage('group-1', '', [
        {'from': 'peer-sender', 'message': replayEnvelope, 'timestamp': 123},
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(bridge.commandLog, contains('group.decrypt'));
      expect(await msgRepo.getMessage('msg-encrypted-hashless-media'), isNull);
      expect(msgRepo.count, 0);
      expect(mediaRepo.count, 0);
    },
  );

  test(
    'skips encrypted replay with dangerous media before message or attachment storage',
    () async {
      final mediaRepo = InMemoryMediaAttachmentRepository();
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'replay-key-1',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      final plaintext = jsonEncode({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Encrypted dangerous media replay',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'messageId': 'msg-encrypted-dangerous-media',
        'media': [
          {
            'id': 'blob-dangerous-1',
            'mime': 'application/pdf',
            'size': 8910,
            'mediaType': 'file',
            'downloadStatus': 'pending',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        ],
      });

      final replayEnvelope = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: plaintext,
        messageId: 'msg-encrypted-dangerous-media',
      );

      bridge.addPage('group-1', '', [
        {'from': 'peer-sender', 'message': replayEnvelope, 'timestamp': 123},
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(bridge.commandLog, contains('group.decrypt'));
      expect(await msgRepo.getMessage('msg-encrypted-dangerous-media'), isNull);
      expect(msgRepo.count, 0);
      expect(mediaRepo.count, 0);
    },
  );

  test(
    'skips encrypted replay with oversized media before message or attachment storage',
    () async {
      final mediaRepo = InMemoryMediaAttachmentRepository();
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'replay-key-1',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      final plaintext = jsonEncode({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Encrypted oversized media replay',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'messageId': 'msg-encrypted-oversized-media',
        'media': [
          {
            'id': 'blob-oversized-replay',
            'mime': 'image/jpeg',
            'size': kGroupMediaPerAttachmentLimitBytes + 1,
            'mediaType': 'image',
            'downloadStatus': 'pending',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        ],
      });

      final replayEnvelope = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: plaintext,
        messageId: 'msg-encrypted-oversized-media',
      );

      bridge.addPage('group-1', '', [
        {'from': 'peer-sender', 'message': replayEnvelope, 'timestamp': 123},
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(bridge.commandLog, contains('group.decrypt'));
      expect(await msgRepo.getMessage('msg-encrypted-oversized-media'), isNull);
      expect(msgRepo.count, 0);
      expect(mediaRepo.count, 0);
    },
  );

  test(
    'drains mixed epoch encrypted replay out of order without rewriting epochs',
    () async {
      final retainedBaseTimestamp = DateTime.now().toUtc().subtract(
        const Duration(days: 1),
      );
      final epoch1Key = GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 1,
        encryptedKey: 'replay-key-1',
        createdAt: DateTime.now().toUtc(),
      );
      final epoch2Key = GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 2,
        encryptedKey: 'replay-key-2',
        createdAt: DateTime.now().toUtc(),
      );
      await groupRepo.saveKey(epoch1Key);
      await groupRepo.saveKey(epoch2Key);

      final epoch1Replay = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        keyGeneration: epoch1Key.keyGeneration,
        plaintext: jsonEncode({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Older epoch replay',
          'timestamp': retainedBaseTimestamp.toIso8601String(),
          'messageId': 'msg-ms018-epoch-1',
        }),
        messageId: 'msg-ms018-epoch-1',
      );
      final epoch2Replay = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        keyGeneration: epoch2Key.keyGeneration,
        plaintext: jsonEncode({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 2,
          'text': 'Newer epoch replay delivered first',
          'timestamp': retainedBaseTimestamp
              .add(const Duration(minutes: 1))
              .toIso8601String(),
          'messageId': 'msg-ms018-epoch-2',
        }),
        messageId: 'msg-ms018-epoch-2',
      );

      bridge.addPage('group-1', '', [
        {'from': 'peer-sender', 'message': epoch2Replay, 'timestamp': 2},
      ], 'older-page');
      bridge.addPage('group-1', 'older-page', [
        {'from': 'peer-sender', 'message': epoch1Replay, 'timestamp': 1},
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      final epoch2Message = await msgRepo.getMessage('msg-ms018-epoch-2');
      final epoch1Message = await msgRepo.getMessage('msg-ms018-epoch-1');
      expect(epoch2Message, isNotNull);
      expect(epoch1Message, isNotNull);
      expect(epoch2Message!.keyGeneration, 2);
      expect(epoch1Message!.keyGeneration, 1);
      expect(epoch2Message.text, 'Newer epoch replay delivered first');
      expect(epoch1Message.text, 'Older epoch replay');

      final decryptCount = bridge.commandLog
          .where((command) => command == 'group.decrypt')
          .length;
      expect(decryptCount, greaterThanOrEqualTo(2));
    },
  );

  test(
    'GI-023 replay uses previous-epoch grace but skips expired replay epoch',
    () async {
      final epoch1Key = GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 1,
        encryptedKey: 'replay-key-1',
        createdAt: DateTime.utc(2026, 5, 1),
      );
      final epoch2Key = GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 2,
        encryptedKey: 'replay-key-2',
        createdAt: DateTime.utc(2026, 5, 2),
      );
      final epoch3Key = GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 3,
        encryptedKey: 'replay-key-3',
        createdAt: DateTime.utc(2026, 5, 3),
      );
      await groupRepo.saveKey(epoch1Key);
      await groupRepo.saveKey(epoch2Key);

      final gracePreviousReplay = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        keyGeneration: 1,
        plaintext: jsonEncode({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'GI-023 previous epoch during grace',
          'timestamp': '2026-05-12T12:00:00.000Z',
          'messageId': 'msg-gi023-grace-epoch-1',
        }),
        messageId: 'msg-gi023-grace-epoch-1',
      );
      final graceCurrentReplay = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        keyGeneration: 2,
        plaintext: jsonEncode({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 2,
          'text': 'GI-023 current epoch during grace',
          'timestamp': '2026-05-12T12:01:00.000Z',
          'messageId': 'msg-gi023-grace-epoch-2',
        }),
        messageId: 'msg-gi023-grace-epoch-2',
      );

      bridge.addPage('group-1', '', [
        {'from': 'peer-sender', 'message': gracePreviousReplay, 'timestamp': 1},
        {'from': 'peer-sender', 'message': graceCurrentReplay, 'timestamp': 2},
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      final gracePrevious = await msgRepo.getMessage('msg-gi023-grace-epoch-1');
      final graceCurrent = await msgRepo.getMessage('msg-gi023-grace-epoch-2');
      expect(gracePrevious, isNotNull);
      expect(gracePrevious!.text, 'GI-023 previous epoch during grace');
      expect(gracePrevious.keyGeneration, 1);
      expect(graceCurrent, isNotNull);
      expect(graceCurrent!.text, 'GI-023 current epoch during grace');
      expect(graceCurrent.keyGeneration, 2);

      await groupRepo.saveKey(epoch3Key);
      expect(await groupRepo.getKeyByGeneration('group-1', 1), isNull);
      expect(await groupRepo.getKeyByGeneration('group-1', 2), isNotNull);
      expect(await groupRepo.getKeyByGeneration('group-1', 3), isNotNull);

      final expiredReplay = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        keyGeneration: 1,
        plaintext: jsonEncode({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'GI-023 expired old epoch must not render',
          'timestamp': '2026-05-12T12:02:00.000Z',
          'messageId': 'msg-gi023-expired-epoch-1',
        }),
        messageId: 'msg-gi023-expired-epoch-1',
      );
      final latestReplay = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        keyGeneration: 3,
        plaintext: jsonEncode({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 3,
          'text': 'GI-023 latest epoch after grace',
          'timestamp': '2026-05-12T12:03:00.000Z',
          'messageId': 'msg-gi023-latest-epoch-3',
        }),
        messageId: 'msg-gi023-latest-epoch-3',
      );
      bridge.addPage('group-1', '', [
        {'from': 'peer-sender', 'message': expiredReplay, 'timestamp': 3},
        {'from': 'peer-sender', 'message': latestReplay, 'timestamp': 4},
      ], '');
      bridge.commandLog.clear();
      bridge.sentMessages.clear();

      final pendingRepo = _InMemoryGroupPendingKeyRepairRepository();
      final repairRequests = <GroupKeyRepairRequest>[];
      final output = <String>[];
      final previousLogging = flowEventLoggingEnabled;
      final originalDebugPrint = debugPrint;
      flowEventLoggingEnabled = true;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) output.add(message);
      };
      addTearDown(() {
        debugPrint = originalDebugPrint;
        flowEventLoggingEnabled = previousLogging;
      });

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        pendingKeyRepairRepo: pendingRepo,
        requestGroupKeyRepair: repairRequests.add,
      );

      expect(await msgRepo.getMessage('msg-gi023-expired-epoch-1'), isNull);
      final latest = await msgRepo.getMessage('msg-gi023-latest-epoch-3');
      expect(latest, isNotNull);
      expect(latest!.text, 'GI-023 latest epoch after grace');
      expect(latest.keyGeneration, 3);
      expect(pendingRepo.repairs, isEmpty);
      expect(repairRequests, isEmpty);
      final uniqueDecryptCommands = bridge.sentMessages.toSet().where((
        message,
      ) {
        final parsed = jsonDecode(message) as Map<String, dynamic>;
        return parsed['cmd'] == 'group.decrypt';
      });
      expect(uniqueDecryptCommands, hasLength(1));

      final visibleMessages = await msgRepo.getMessagesPage('group-1');
      expect(
        visibleMessages.where(
          (message) => message.text.contains('expired old epoch'),
        ),
        isEmpty,
      );

      final events = output
          .where((line) => line.startsWith('[FLOW] '))
          .map(
            (line) =>
                jsonDecode(line.substring('[FLOW] '.length))
                    as Map<String, dynamic>,
          )
          .toList();
      final staleEvent = events.firstWhere(
        (event) =>
            event['event'] ==
            'GROUP_DRAIN_OFFLINE_INBOX_STALE_REPLAY_EPOCH_SKIPPED',
      );
      expect(staleEvent['details']['keyEpoch'], 1);
      expect(staleEvent['details']['latestKeyGeneration'], 3);
      expect(staleEvent['details']['minAcceptedKeyGeneration'], 2);
    },
  );

  test(
    'GI-024 duplicate replay is idempotent without status rollback or notification spam',
    () async {
      await saveDefaultReplayKey();

      const messageId = 'msg-gi024-duplicate-old-replay';
      const messageText = 'GI-024 original replay body';
      final sentAt = DateTime.utc(2026, 5, 12, 13);
      final replayEnvelope = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: jsonEncode({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': messageText,
          'timestamp': sentAt.toIso8601String(),
          'messageId': messageId,
        }),
        messageId: messageId,
      );

      final notifService = FakeNotificationService();
      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        notificationService: notifService,
        groupConversationTracker: ActiveConversationTracker(),
        getAppLifecycleState: () => AppLifecycleState.paused,
      );
      final replayedMessages = <GroupMessage>[];
      final subscription = listener.groupMessageStream.listen(
        replayedMessages.add,
      );
      Future<void> waitForNotificationCount(int count) async {
        final deadline = DateTime.now().add(const Duration(seconds: 1));
        while (notifService.shown.length < count &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      addTearDown(() async {
        await subscription.cancel();
        listener.dispose();
      });

      bridge.addPage('group-1', '', [
        {'from': 'peer-sender', 'message': replayEnvelope, 'timestamp': 1},
        {'from': 'peer-sender', 'message': replayEnvelope, 'timestamp': 2},
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
      );
      await waitForNotificationCount(1);

      expect(msgRepo.count, 1);
      expect(replayedMessages, hasLength(1));
      expect(notifService.shown, hasLength(1));
      expect(notifService.shown.single.contactPeerId, 'group:group-1');
      expect(notifService.shown.single.messageText, contains(messageText));

      final stored = await msgRepo.getMessage(messageId);
      expect(stored, isNotNull);
      expect(stored!.text, messageText);
      expect(stored.timestamp, sentAt);
      expect(stored.senderPeerId, 'peer-sender');
      expect(stored.status, 'delivered');
      expect(stored.isIncoming, isTrue);
      expect(stored.readAt, isNull);

      await msgRepo.markAsRead('group-1');
      final readMessage = await msgRepo.getMessage(messageId);
      final readAt = readMessage!.readAt;
      expect(readAt, isNotNull);

      bridge.addPage('group-1', '', [
        {'from': 'peer-sender', 'message': replayEnvelope, 'timestamp': 3},
        {'from': 'peer-sender', 'message': replayEnvelope, 'timestamp': 4},
      ], '');
      bridge.commandLog.clear();
      bridge.sentMessages.clear();

      final output = <String>[];
      final previousLogging = flowEventLoggingEnabled;
      final originalDebugPrint = debugPrint;
      flowEventLoggingEnabled = true;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) output.add(message);
      };
      addTearDown(() {
        debugPrint = originalDebugPrint;
        flowEventLoggingEnabled = previousLogging;
      });

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final afterReplay = await msgRepo.getMessage(messageId);
      expect(msgRepo.count, 1);
      expect(afterReplay, isNotNull);
      expect(afterReplay!.text, messageText);
      expect(afterReplay.timestamp, sentAt);
      expect(afterReplay.senderPeerId, 'peer-sender');
      expect(afterReplay.status, 'delivered');
      expect(afterReplay.isIncoming, isTrue);
      expect(afterReplay.readAt, readAt);
      expect(replayedMessages, hasLength(1));
      expect(notifService.shown, hasLength(1));

      final events = output
          .where((line) => line.startsWith('[FLOW] '))
          .map(
            (line) =>
                jsonDecode(line.substring('[FLOW] '.length))
                    as Map<String, dynamic>,
          )
          .toList();
      final duplicateEvents = events.where(
        (event) =>
            event['event'] == 'GROUP_HANDLE_INCOMING_MSG_DUPLICATE' &&
            (event['details'] as Map<String, dynamic>)['dedupeBy'] ==
                'messageId',
      );
      expect(duplicateEvents, hasLength(2));
    },
  );

  test(
    'GI-034 offline replay suppresses duplicate notifications and preserves unread state',
    () async {
      await saveDefaultReplayKey();

      const pushedMessageId = 'msg-gi034-remote-push-replayed';
      const localMessageId = 'msg-gi034-local-replay';
      const pushedMessageText = 'GI-034 already announced remotely';
      const localMessageText = 'GI-034 needs one local alert';
      final pushedSentAt = DateTime.utc(2026, 5, 12, 14);
      final localSentAt = DateTime.utc(2026, 5, 12, 14, 1);
      final pushedReplay = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: jsonEncode({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': pushedMessageText,
          'timestamp': pushedSentAt.toIso8601String(),
          'messageId': pushedMessageId,
        }),
        messageId: pushedMessageId,
      );
      final localReplay = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: jsonEncode({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': localMessageText,
          'timestamp': localSentAt.toIso8601String(),
          'messageId': localMessageId,
        }),
        messageId: localMessageId,
      );

      final remoteGate = RecentRemoteNotificationGate(
        filePath:
            '${Directory.systemTemp.path}/gi034-remote-gate-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      await remoteGate.markAnnouncement(
        payload: 'group:group-1|message:$pushedMessageId',
        messageId: pushedMessageId,
      );
      addTearDown(remoteGate.clear);

      final notifService = FakeNotificationService();
      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        notificationService: notifService,
        groupConversationTracker: ActiveConversationTracker(),
        getAppLifecycleState: () => AppLifecycleState.paused,
        remoteNotificationGate: remoteGate,
      );
      final replayedMessages = <GroupMessage>[];
      final subscription = listener.groupMessageStream.listen(
        replayedMessages.add,
      );
      Future<void> waitForNotificationCount(int count) async {
        final deadline = DateTime.now().add(const Duration(seconds: 1));
        while (notifService.shown.length < count &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      addTearDown(() async {
        await subscription.cancel();
        listener.dispose();
      });

      bridge.addPage('group-1', '', [
        {'from': 'peer-sender', 'message': pushedReplay, 'timestamp': 1},
        {'from': 'peer-sender', 'message': pushedReplay, 'timestamp': 2},
        {'from': 'peer-sender', 'message': localReplay, 'timestamp': 3},
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
      );
      await waitForNotificationCount(1);

      expect(msgRepo.count, 2);
      expect(replayedMessages.map((message) => message.id), [
        pushedMessageId,
        localMessageId,
      ]);
      expect(notifService.shown, hasLength(1));
      expect(notifService.shown.single.contactPeerId, 'group:group-1');
      expect(notifService.shown.single.messageText, contains(localMessageText));
      expect(
        notifService.shown.single.messageText,
        isNot(contains(pushedMessageText)),
      );
      expect(await msgRepo.getUnreadCount('group-1'), 2);
      expect(await msgRepo.getTotalUnreadCount(), 2);
      expect(
        await remoteGate.consumeIfRecentAnnouncement(
          payload: 'group:group-1|message:$pushedMessageId',
          messageId: pushedMessageId,
        ),
        isFalse,
        reason: 'The replay listener should consume the remote-push marker.',
      );

      await msgRepo.markAsRead('group-1');
      expect(await msgRepo.getUnreadCount('group-1'), 0);

      bridge.addPage('group-1', '', [
        {'from': 'peer-sender', 'message': pushedReplay, 'timestamp': 4},
        {'from': 'peer-sender', 'message': localReplay, 'timestamp': 5},
      ], '');
      bridge.commandLog.clear();
      bridge.sentMessages.clear();

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(msgRepo.count, 2);
      expect(replayedMessages.map((message) => message.id), [
        pushedMessageId,
        localMessageId,
      ]);
      expect(notifService.shown, hasLength(1));
      expect(await msgRepo.getUnreadCount('group-1'), 0);
      expect(await msgRepo.getTotalUnreadCount(), 0);
      expect((await msgRepo.getMessage(pushedMessageId))!.readAt, isNotNull);
      expect((await msgRepo.getMessage(localMessageId))!.readAt, isNotNull);
    },
  );

  test(
    'PREREQ-FUTURE-EPOCH-KEY-REPAIR future epoch replay queues and repairs after key arrival',
    () async {
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'replay-key-1',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      final futureEpochKey = GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 2,
        encryptedKey: 'replay-key-2',
        createdAt: DateTime.now().toUtc(),
      );
      final replayEnvelope = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        keyGeneration: futureEpochKey.keyGeneration,
        plaintext: jsonEncode({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 2,
          'text': 'Future epoch replay repaired',
          'timestamp': '2026-05-01T12:02:00.000Z',
          'messageId': 'msg-prereq-future-repair',
        }),
        messageId: 'msg-prereq-future-repair',
      );
      bridge.addPage('group-1', '', [
        {'from': 'peer-sender', 'message': replayEnvelope, 'timestamp': 2},
        {'from': 'peer-sender', 'message': replayEnvelope, 'timestamp': 3},
      ], '');
      final pendingRepo = _InMemoryGroupPendingKeyRepairRepository();
      final repairRequests = <GroupKeyRepairRequest>[];

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        pendingKeyRepairRepo: pendingRepo,
        requestGroupKeyRepair: (request) {
          repairRequests.add(request);
        },
      );

      final pendingPlaceholder = await msgRepo.getMessage(
        'msg-prereq-future-repair',
      );
      expect(pendingPlaceholder, isNotNull);
      expect(pendingPlaceholder!.text, groupPendingKeyRepairPlaceholderText);
      expect(pendingPlaceholder.status, groupPendingKeyRepairStatusPendingKey);
      expect(pendingPlaceholder.keyGeneration, 2);
      expect(msgRepo.count, 1);
      expect(pendingRepo.repairs.values, hasLength(1));
      expect(repairRequests, hasLength(1));
      expect(repairRequests.single.groupId, 'group-1');
      expect(repairRequests.single.keyEpoch, 2);
      expect(repairRequests.single.messageId, 'msg-prereq-future-repair');
      expect(bridge.commandLog, isNot(contains('group.decrypt')));

      await groupRepo.saveKey(futureEpochKey);
      final runner = GroupPendingKeyRepairRunner(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        pendingKeyRepairRepo: pendingRepo,
      );

      final repairedCount = await runner.retryPendingRepairsForKey(
        groupId: 'group-1',
        keyEpoch: 2,
      );

      expect(repairedCount, 1);
      final repairedMessage = await msgRepo.getMessage(
        'msg-prereq-future-repair',
      );
      expect(repairedMessage, isNotNull);
      expect(repairedMessage!.text, 'Future epoch replay repaired');
      expect(repairedMessage.status, 'delivered');
      expect(repairedMessage.keyGeneration, 2);
      expect(msgRepo.count, 1);
      expect(bridge.commandLog, contains('group.decrypt'));
      final repair = pendingRepo.repairs.values.single;
      expect(repair.status, groupPendingKeyRepairStatusRepaired);
      expect(repair.finalizedAt, isNotNull);
    },
  );

  test(
    'GEK002 live decrypt failure plus durable replay repairs one visible message after key arrival',
    () async {
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'replay-key-1',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      final futureEpochKey = GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 2,
        encryptedKey: 'replay-key-2',
        createdAt: DateTime.now().toUtc(),
      );
      final pendingRepo = _InMemoryGroupPendingKeyRepairRepository();
      final repairRequests = <GroupKeyRepairRequest>[];
      final diagnostics = StreamController<Map<String, dynamic>>.broadcast();
      final liveMessages = StreamController<Map<String, dynamic>>.broadcast();
      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        groupDiagnosticEvents: diagnostics.stream,
        pendingKeyRepairRepo: pendingRepo,
        requestGroupKeyRepair: (request) {
          repairRequests.add(request);
        },
      );
      listener.start(liveMessages.stream);
      addTearDown(() async {
        listener.dispose();
        await diagnostics.close();
        await liveMessages.close();
      });

      final livePlaceholderFuture = listener.groupMessageStream.first.timeout(
        const Duration(seconds: 1),
      );
      diagnostics.add({
        'event': 'group:decryption_failed',
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'keyEpoch': 2,
        'localKeyEpoch': 1,
        'error': 'cipher: message authentication failed',
      });

      final livePlaceholder = await livePlaceholderFuture;
      final liveRepairId = liveGroupPendingKeyRepairId(
        groupId: 'group-1',
        senderPeerId: 'peer-sender',
        keyEpoch: 2,
        localKeyEpoch: 1,
      );
      expect(livePlaceholder.id, liveRepairId);
      expect(livePlaceholder.text, groupPendingKeyRepairPlaceholderText);
      expect(livePlaceholder.status, groupPendingKeyRepairStatusPendingKey);
      expect(await msgRepo.getMessage('msg-gek002-replay'), isNull);
      expect(msgRepo.count, 1);
      expect(repairRequests, hasLength(1));
      expect(repairRequests.single.reason, groupKeyRepairReasonLiveDiagnostic);

      final replayEnvelope = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        keyGeneration: futureEpochKey.keyGeneration,
        plaintext: jsonEncode({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 2,
          'text': 'GEK002 repaired from durable replay',
          'timestamp': '2026-05-01T12:03:00.000Z',
          'messageId': 'msg-gek002-replay',
        }),
        messageId: 'msg-gek002-replay',
      );
      bridge.addPage('group-1', '', [
        {'from': 'peer-sender', 'message': replayEnvelope, 'timestamp': 2},
        {'from': 'peer-sender', 'message': replayEnvelope, 'timestamp': 3},
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
        pendingKeyRepairRepo: pendingRepo,
        requestGroupKeyRepair: (request) {
          repairRequests.add(request);
        },
      );

      final durablePlaceholder = await msgRepo.getMessage('msg-gek002-replay');
      expect(durablePlaceholder, isNotNull);
      expect(durablePlaceholder!.text, groupPendingKeyRepairPlaceholderText);
      expect(durablePlaceholder.status, groupPendingKeyRepairStatusPendingKey);
      expect(durablePlaceholder.keyGeneration, 2);
      expect(await msgRepo.getMessage(liveRepairId), isNull);
      final visibleAfterReplay = await msgRepo.getMessagesPage('group-1');
      expect(visibleAfterReplay, hasLength(1));
      expect(visibleAfterReplay.single.id, 'msg-gek002-replay');
      final pendingRepairs = await pendingRepo.getPendingRepairsForGroupEpoch(
        groupId: 'group-1',
        keyEpoch: 2,
      );
      expect(pendingRepairs, hasLength(1));
      expect(pendingRepairs.single.messageId, 'msg-gek002-replay');
      expect(repairRequests, hasLength(2));
      expect(repairRequests.last.reason, groupKeyRepairReasonOfflineMissingKey);
      expect(repairRequests.last.messageId, 'msg-gek002-replay');

      await groupRepo.saveKey(futureEpochKey);
      final runner = GroupPendingKeyRepairRunner(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        pendingKeyRepairRepo: pendingRepo,
        replayGroupEnvelope: listener.handleReplayEnvelope,
      );

      final repairedCount = await runner.retryPendingRepairsForKey(
        groupId: 'group-1',
        keyEpoch: 2,
      );

      expect(repairedCount, 1);
      final repairedMessage = await msgRepo.getMessage('msg-gek002-replay');
      expect(repairedMessage, isNotNull);
      expect(repairedMessage!.text, 'GEK002 repaired from durable replay');
      expect(repairedMessage.senderPeerId, 'peer-sender');
      expect(repairedMessage.transportPeerId, 'peer-sender');
      expect(repairedMessage.status, 'delivered');
      expect(repairedMessage.keyGeneration, 2);
      expect(await msgRepo.getMessage(liveRepairId), isNull);
      final visibleAfterRepair = await msgRepo.getMessagesPage('group-1');
      expect(visibleAfterRepair, hasLength(1));
      expect(visibleAfterRepair.single.id, 'msg-gek002-replay');

      final secondRetryCount = await runner.retryPendingRepairsForKey(
        groupId: 'group-1',
        keyEpoch: 2,
      );
      expect(secondRetryCount, 0);
      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
        pendingKeyRepairRepo: pendingRepo,
      );
      final visibleAfterDuplicateReplay = await msgRepo.getMessagesPage(
        'group-1',
      );
      expect(visibleAfterDuplicateReplay, hasLength(1));
      expect(visibleAfterDuplicateReplay.single.id, 'msg-gek002-replay');
    },
  );

  test(
    'GEK004 delayed membership config catch-up recovers newly accepted sender durable message exactly once',
    () async {
      const groupId = 'group-1';
      const adminPeerId = 'peer-admin';
      const newPeerId = 'peer-new-sender';
      const newDeviceId = 'device-new-sender';
      const newMessageId = 'msg-gek004-new-sender';
      const memberAddedMessageId = 'sys-gek004-member-added';
      final joinedAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 5),
      );
      final groupCreatedAt = joinedAt.subtract(const Duration(minutes: 15));
      final messageAt = joinedAt.add(const Duration(minutes: 1));

      await saveDefaultReplayKey();
      await groupRepo.updateGroup(
        testGroup.copyWith(createdAt: groupCreatedAt),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: adminPeerId,
          username: 'Admin',
          role: MemberRole.admin,
          publicKey: 'pk-admin',
          joinedAt: joinedAt.subtract(const Duration(minutes: 10)),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-sender',
          username: 'Sender',
          role: MemberRole.writer,
          publicKey: 'pk-sender',
          joinedAt: joinedAt.subtract(const Duration(minutes: 9)),
        ),
      );

      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
      );
      addTearDown(listener.dispose);

      final newMemberConfig = {
        'peerId': newPeerId,
        'username': 'New Sender',
        'role': 'writer',
        'publicKey': 'pk-new-sender',
        'devices': [
          {
            'deviceId': newDeviceId,
            'transportPeerId': newDeviceId,
            'deviceSigningPublicKey': 'pk-new-sender',
            'mlKemPublicKey': 'mlkem-new-sender',
            'keyPackageId': 'key-package-new-sender',
            'keyPackagePublicMaterial': 'key-package-public-new-sender',
          },
        ],
      };
      final groupConfig = {
        'name': 'Test Group',
        'groupType': 'chat',
        'members': [
          {
            'peerId': adminPeerId,
            'username': 'Admin',
            'role': 'admin',
            'publicKey': 'pk-admin',
          },
          {
            'peerId': 'peer-sender',
            'username': 'Sender',
            'role': 'writer',
            'publicKey': 'pk-sender',
          },
          newMemberConfig,
        ],
        'createdBy': adminPeerId,
        'createdAt': groupCreatedAt.toIso8601String(),
      };

      final durableReplay = await buildGroupOfflineReplayEnvelope(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: jsonEncode({
          'groupId': groupId,
          'senderId': newPeerId,
          'senderUsername': 'New Sender',
          'senderDeviceId': newDeviceId,
          'transportPeerId': newDeviceId,
          'keyEpoch': 1,
          'text': 'GEK004 post-join durable message',
          'timestamp': messageAt.toIso8601String(),
          'messageId': newMessageId,
        }),
        messageId: newMessageId,
        senderPeerId: newPeerId,
        senderPublicKey: 'pk-new-sender',
        senderPrivateKey: 'sk-new-sender',
        senderDeviceId: newDeviceId,
        senderTransportPeerId: newDeviceId,
        keyInfo: GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'replay-key-1',
          createdAt: joinedAt,
        ),
      );
      final memberAddedReplay = await buildGroupOfflineReplayEnvelope(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: jsonEncode({
          'groupId': groupId,
          'senderId': adminPeerId,
          'senderUsername': 'Admin',
          'keyEpoch': 1,
          'text': jsonEncode({
            '__sys': 'member_added',
            'member': newMemberConfig,
            'groupConfig': groupConfig,
          }),
          'timestamp': joinedAt.toIso8601String(),
          'messageId': memberAddedMessageId,
        }),
        messageId: memberAddedMessageId,
        senderPeerId: adminPeerId,
        senderPublicKey: 'pk-admin',
        senderPrivateKey: 'sk-admin',
        keyInfo: GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'replay-key-1',
          createdAt: joinedAt,
        ),
      );

      bridge.addPage(groupId, '', [
        {'from': newDeviceId, 'message': durableReplay, 'timestamp': 1},
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
      );

      expect(await groupRepo.getMember(groupId, newPeerId), isNull);
      expect(await msgRepo.getMessage(newMessageId), isNull);
      expect(await msgRepo.getInboxCursor(groupId), isNull);

      bridge.addPage(groupId, '', [
        {'from': newDeviceId, 'message': durableReplay, 'timestamp': 1},
        {'from': adminPeerId, 'message': memberAddedReplay, 'timestamp': 2},
        {'from': newDeviceId, 'message': durableReplay, 'timestamp': 3},
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
      );

      final caughtUpMember = await groupRepo.getMember(groupId, newPeerId);
      expect(caughtUpMember, isNotNull);
      expect(caughtUpMember!.username, 'New Sender');
      expect(caughtUpMember.findDeviceById(newDeviceId), isNotNull);

      final deliveredMessage = await msgRepo.getMessage(newMessageId);
      expect(deliveredMessage, isNotNull);
      expect(deliveredMessage!.groupId, groupId);
      expect(deliveredMessage.senderPeerId, newPeerId);
      expect(deliveredMessage.transportPeerId, newDeviceId);
      expect(deliveredMessage.senderUsername, 'New Sender');
      expect(deliveredMessage.text, 'GEK004 post-join durable message');
      expect(deliveredMessage.status, 'delivered');
      expect(deliveredMessage.keyGeneration, 1);
      expect(deliveredMessage.timestamp, messageAt);
      expect(deliveredMessage.isIncoming, isTrue);

      final visibleAfterCatchUp = await msgRepo.getMessagesPage(groupId);
      expect(
        visibleAfterCatchUp.where((message) => message.id == newMessageId),
        hasLength(1),
      );

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
      );

      final visibleAfterDuplicateReplay = await msgRepo.getMessagesPage(
        groupId,
      );
      expect(
        visibleAfterDuplicateReplay.where(
          (message) => message.id == newMessageId,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'GEK003 partial key-update delivery plus immediate post-rotation send repairs stale recipient after later key arrival',
    () async {
      const groupId = 'group-gek003';
      const alicePeerId = 'peer-alice';
      const bobPeerId = 'peer-bob';
      const charliePeerId = 'peer-charlie';
      const removedPeerId = 'peer-removed';
      const aliceDeviceId = 'device-alice';
      const bobDeviceId = 'device-bob';
      const charlieDeviceId = 'device-charlie';
      const removedDeviceId = 'device-removed';
      const bobMessageId = 'msg-gek003-bob';
      const bobMessageText = 'GEK003 Bob sends on epoch 2';
      final groupCreatedAt = DateTime.utc(2026, 5, 9, 18);
      final messageAt = DateTime.utc(2026, 5, 9, 18, 3);

      GroupMemberDeviceIdentity deviceIdentity(String peerId, String deviceId) {
        return GroupMemberDeviceIdentity(
          deviceId: deviceId,
          transportPeerId: deviceId,
          deviceSigningPublicKey: 'pk-$peerId',
          mlKemPublicKey: 'mlkem-$deviceId',
          keyPackageId: 'key-package-$deviceId',
          keyPackagePublicMaterial: 'key-package-public-$deviceId',
        );
      }

      GroupMember member({
        required String peerId,
        required String username,
        required MemberRole role,
        required String deviceId,
        required DateTime joinedAt,
      }) {
        return GroupMember(
          groupId: groupId,
          peerId: peerId,
          username: username,
          role: role,
          publicKey: 'pk-$peerId',
          mlKemPublicKey: 'mlkem-$peerId',
          devices: [deviceIdentity(peerId, deviceId)],
          joinedAt: joinedAt,
        );
      }

      final aliceMember = member(
        peerId: alicePeerId,
        username: 'Alice',
        role: MemberRole.admin,
        deviceId: aliceDeviceId,
        joinedAt: groupCreatedAt,
      );
      final bobMember = member(
        peerId: bobPeerId,
        username: 'Bob',
        role: MemberRole.writer,
        deviceId: bobDeviceId,
        joinedAt: groupCreatedAt.add(const Duration(minutes: 1)),
      );
      final charlieMember = member(
        peerId: charliePeerId,
        username: 'Charlie',
        role: MemberRole.writer,
        deviceId: charlieDeviceId,
        joinedAt: groupCreatedAt.add(const Duration(minutes: 2)),
      );
      final removedMember = member(
        peerId: removedPeerId,
        username: 'Removed',
        role: MemberRole.writer,
        deviceId: removedDeviceId,
        joinedAt: groupCreatedAt.add(const Duration(minutes: 3)),
      );

      Future<void> seedGroupContext({
        required InMemoryGroupRepository repository,
        required GroupRole myRole,
      }) async {
        await repository.saveGroup(
          GroupModel(
            id: groupId,
            name: 'GEK003 Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/$groupId',
            createdAt: groupCreatedAt,
            createdBy: alicePeerId,
            myRole: myRole,
          ),
        );
        for (final activeMember in [aliceMember, bobMember, charlieMember]) {
          await repository.saveMember(activeMember);
        }
        await repository.saveMember(removedMember);
        await repository.removeMember(groupId, removedPeerId);
        await repository.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'gek003-key-epoch-1',
            createdAt: groupCreatedAt,
          ),
        );
      }

      Map<String, dynamic> lastCommandPayload(
        _CursorInboxBridge sourceBridge,
        String command,
      ) {
        final raw = sourceBridge.sentMessages.lastWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == command;
        });
        final parsed = jsonDecode(raw) as Map<String, dynamic>;
        return parsed['payload'] as Map<String, dynamic>;
      }

      ChatMessage keyUpdateChatMessage({
        required String content,
        required String toDeviceId,
      }) {
        return ChatMessage(
          from: aliceDeviceId,
          to: toDeviceId,
          content: content,
          timestamp: groupCreatedAt
              .add(const Duration(minutes: 4))
              .toUtc()
              .toIso8601String(),
          isIncoming: true,
        );
      }

      Future<GroupKeyInfo> waitForLatestKey(
        InMemoryGroupRepository repository,
        int generation,
      ) async {
        for (var attempt = 0; attempt < 30; attempt++) {
          final latestKey = await repository.getLatestKey(groupId);
          if (latestKey?.keyGeneration == generation) {
            return latestKey!;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        fail('Timed out waiting for $groupId key generation $generation');
      }

      Future<GroupMessage> waitForMessageStatus(
        InMemoryGroupMessageRepository repository,
        String messageId,
        String status,
      ) async {
        for (var attempt = 0; attempt < 30; attempt++) {
          final message = await repository.getMessage(messageId);
          if (message?.status == status) {
            return message!;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        fail('Timed out waiting for $messageId status $status');
      }

      final aliceRepo = InMemoryGroupRepository();
      final bobRepo = InMemoryGroupRepository();
      final charlieRepo = InMemoryGroupRepository();
      final aliceMsgRepo = InMemoryGroupMessageRepository();
      final bobMsgRepo = InMemoryGroupMessageRepository();
      final charlieMsgRepo = InMemoryGroupMessageRepository();
      final aliceBridge = _CursorInboxBridge();
      final bobBridge = _CursorInboxBridge();
      final charlieBridge = _CursorInboxBridge();
      configureLegacyReplaySigning(aliceBridge);
      configureLegacyReplaySigning(bobBridge);
      configureLegacyReplaySigning(charlieBridge);

      await seedGroupContext(repository: aliceRepo, myRole: GroupRole.admin);
      await seedGroupContext(repository: bobRepo, myRole: GroupRole.member);
      await seedGroupContext(repository: charlieRepo, myRole: GroupRole.member);

      aliceBridge.responses['group:generateNextKey'] = {
        'ok': true,
        'groupKey': 'gek003-key-epoch-2',
        'keyEpoch': 2,
      };
      aliceBridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'sys-gek003-key-rotated',
        'topicPeers': 2,
      };

      final capturedKeyUpdatesByDevice = <String, String>{};
      final rotatedKey = await rotateAndDistributeGroupKey(
        bridge: aliceBridge,
        groupRepo: aliceRepo,
        groupId: groupId,
        selfPeerId: alicePeerId,
        senderPublicKey: 'pk-$alicePeerId',
        senderPrivateKey: 'sk-$alicePeerId',
        senderUsername: 'Alice',
        sourceDeviceId: aliceDeviceId,
        sendP2PMessage: (transportPeerId, message) async {
          capturedKeyUpdatesByDevice[transportPeerId] = message;
          return true;
        },
      );

      expect(rotatedKey, isNotNull);
      expect(rotatedKey!.keyGeneration, 2);
      expect(
        capturedKeyUpdatesByDevice.keys,
        unorderedEquals([bobDeviceId, charlieDeviceId]),
      );
      expect(capturedKeyUpdatesByDevice.keys, isNot(contains(aliceDeviceId)));
      expect(capturedKeyUpdatesByDevice.keys, isNot(contains(removedDeviceId)));
      expect((await aliceRepo.getLatestKey(groupId))!.keyGeneration, 2);

      final bobKeyUpdates = StreamController<ChatMessage>.broadcast();
      final bobKeyUpdateListener = GroupKeyUpdateListener(
        groupKeyUpdateStream: bobKeyUpdates.stream,
        groupRepo: bobRepo,
        bridge: bobBridge,
        getOwnMlKemSecretKey: () async => 'mlkem-secret-$bobDeviceId',
        getOwnPeerId: () async => bobPeerId,
        getOwnDeviceId: () async => bobDeviceId,
      );
      bobKeyUpdateListener.start();
      addTearDown(() async {
        bobKeyUpdateListener.dispose();
        await bobKeyUpdates.close();
      });
      bobKeyUpdates.add(
        keyUpdateChatMessage(
          content: capturedKeyUpdatesByDevice[bobDeviceId]!,
          toDeviceId: bobDeviceId,
        ),
      );
      final bobCommittedKey = await waitForLatestKey(bobRepo, 2);
      expect(bobCommittedKey.encryptedKey, 'gek003-key-epoch-2');
      expect((await charlieRepo.getLatestKey(groupId))!.keyGeneration, 1);

      bobBridge.responses['group:publish'] = {
        'ok': true,
        'messageId': bobMessageId,
        'topicPeers': 2,
      };
      final (sendResult, bobMessage) = await sendGroupMessage(
        bridge: bobBridge,
        groupRepo: bobRepo,
        msgRepo: bobMsgRepo,
        groupId: groupId,
        text: bobMessageText,
        senderPeerId: bobPeerId,
        senderDeviceId: bobDeviceId,
        senderTransportPeerId: bobDeviceId,
        senderPublicKey: 'pk-$bobPeerId',
        senderPrivateKey: 'sk-$bobPeerId',
        senderUsername: 'Bob',
        messageId: bobMessageId,
        timestamp: messageAt,
      );

      expect(sendResult, SendGroupMessageResult.success);
      expect(bobMessage, isNotNull);
      expect(bobMessage!.keyGeneration, 2);
      final savedBobMessage = await bobMsgRepo.getMessage(bobMessageId);
      expect(savedBobMessage, isNotNull);
      expect(savedBobMessage!.keyGeneration, 2);
      final bobInboxStorePayload = lastCommandPayload(
        bobBridge,
        'group:inboxStore',
      );
      final replayEnvelope = bobInboxStorePayload['message'] as String;
      final replayEnvelopeJson =
          jsonDecode(replayEnvelope) as Map<String, dynamic>;
      expect(replayEnvelopeJson['keyEpoch'], 2);
      expect(replayEnvelopeJson['messageId'], bobMessageId);
      expect(replayEnvelopeJson['senderPeerId'], bobPeerId);
      expect(replayEnvelopeJson['senderDeviceId'], bobDeviceId);
      expect(replayEnvelopeJson['senderTransportPeerId'], bobDeviceId);
      expect(
        (bobInboxStorePayload['recipientPeerIds'] as List<dynamic>)
            .cast<String>(),
        unorderedEquals([alicePeerId, charliePeerId]),
      );

      aliceBridge.addPage(groupId, '', [
        {'from': bobDeviceId, 'message': replayEnvelope, 'timestamp': 2},
      ], '');
      await drainGroupOfflineInbox(
        bridge: aliceBridge,
        groupRepo: aliceRepo,
        msgRepo: aliceMsgRepo,
      );
      final aliceReceived = await aliceMsgRepo.getMessage(bobMessageId);
      expect(aliceReceived, isNotNull);
      expect(aliceReceived!.text, bobMessageText);
      expect(aliceReceived.status, 'delivered');
      expect(aliceReceived.keyGeneration, 2);
      expect(aliceReceived.senderPeerId, bobPeerId);
      expect(aliceReceived.transportPeerId, bobDeviceId);
      expect(await aliceMsgRepo.getMessagesPage(groupId), hasLength(1));

      final pendingRepo = _InMemoryGroupPendingKeyRepairRepository();
      final repairRequests = <GroupKeyRepairRequest>[];
      final diagnostics = StreamController<Map<String, dynamic>>.broadcast();
      final liveMessages = StreamController<Map<String, dynamic>>.broadcast();
      final charlieMessageListener = GroupMessageListener(
        groupRepo: charlieRepo,
        msgRepo: charlieMsgRepo,
        bridge: charlieBridge,
        getSelfPeerId: () async => charliePeerId,
        groupDiagnosticEvents: diagnostics.stream,
        pendingKeyRepairRepo: pendingRepo,
        requestGroupKeyRepair: (request) {
          repairRequests.add(request);
        },
      );
      charlieMessageListener.start(liveMessages.stream);
      addTearDown(() async {
        charlieMessageListener.dispose();
        await diagnostics.close();
        await liveMessages.close();
      });

      final livePlaceholderFuture = charlieMessageListener
          .groupMessageStream
          .first
          .timeout(const Duration(seconds: 1));
      diagnostics.add({
        'event': 'group:decryption_failed',
        'groupId': groupId,
        'senderId': bobPeerId,
        'keyEpoch': 2,
        'localKeyEpoch': 1,
        'error': 'cipher: message authentication failed',
      });
      final livePlaceholder = await livePlaceholderFuture;
      final liveRepairId = liveGroupPendingKeyRepairId(
        groupId: groupId,
        senderPeerId: bobPeerId,
        keyEpoch: 2,
        localKeyEpoch: 1,
      );
      expect(livePlaceholder.id, liveRepairId);
      expect(livePlaceholder.text, groupPendingKeyRepairPlaceholderText);
      expect(livePlaceholder.status, groupPendingKeyRepairStatusPendingKey);
      expect(await charlieMsgRepo.getMessage(bobMessageId), isNull);
      expect(repairRequests, hasLength(1));
      expect(repairRequests.single.reason, groupKeyRepairReasonLiveDiagnostic);

      charlieBridge.addPage(groupId, '', [
        {'from': bobDeviceId, 'message': replayEnvelope, 'timestamp': 2},
        {'from': bobDeviceId, 'message': replayEnvelope, 'timestamp': 3},
      ], '');
      await drainGroupOfflineInbox(
        bridge: charlieBridge,
        groupRepo: charlieRepo,
        msgRepo: charlieMsgRepo,
        groupMessageListener: charlieMessageListener,
        pendingKeyRepairRepo: pendingRepo,
        requestGroupKeyRepair: (request) {
          repairRequests.add(request);
        },
      );

      final durablePlaceholder = await charlieMsgRepo.getMessage(bobMessageId);
      expect(durablePlaceholder, isNotNull);
      expect(durablePlaceholder!.text, groupPendingKeyRepairPlaceholderText);
      expect(durablePlaceholder.status, groupPendingKeyRepairStatusPendingKey);
      expect(durablePlaceholder.keyGeneration, 2);
      expect(durablePlaceholder.senderPeerId, bobPeerId);
      expect(durablePlaceholder.transportPeerId, bobDeviceId);
      expect(await charlieMsgRepo.getMessage(liveRepairId), isNull);
      final visibleAfterReplay = await charlieMsgRepo.getMessagesPage(groupId);
      expect(visibleAfterReplay, hasLength(1));
      expect(visibleAfterReplay.single.id, bobMessageId);
      final pendingRepairs = await pendingRepo.getPendingRepairsForGroupEpoch(
        groupId: groupId,
        keyEpoch: 2,
      );
      expect(pendingRepairs, hasLength(1));
      expect(pendingRepairs.single.messageId, bobMessageId);
      expect(repairRequests, hasLength(2));
      expect(repairRequests.last.reason, groupKeyRepairReasonOfflineMissingKey);
      expect(repairRequests.last.messageId, bobMessageId);

      final charlieRepairRunner = GroupPendingKeyRepairRunner(
        bridge: charlieBridge,
        groupRepo: charlieRepo,
        msgRepo: charlieMsgRepo,
        pendingKeyRepairRepo: pendingRepo,
        replayGroupEnvelope: charlieMessageListener.handleReplayEnvelope,
      );
      final charlieKeyUpdates = StreamController<ChatMessage>.broadcast();
      final charlieKeyUpdateListener = GroupKeyUpdateListener(
        groupKeyUpdateStream: charlieKeyUpdates.stream,
        groupRepo: charlieRepo,
        bridge: charlieBridge,
        getOwnMlKemSecretKey: () async => 'mlkem-secret-$charlieDeviceId',
        getOwnPeerId: () async => charliePeerId,
        getOwnDeviceId: () async => charlieDeviceId,
        retryPendingGroupKeyRepairs:
            charlieRepairRunner.retryPendingRepairsForRequest,
      );
      charlieKeyUpdateListener.start();
      addTearDown(() async {
        charlieKeyUpdateListener.dispose();
        await charlieKeyUpdates.close();
      });

      charlieKeyUpdates.add(
        keyUpdateChatMessage(
          content: capturedKeyUpdatesByDevice[charlieDeviceId]!,
          toDeviceId: charlieDeviceId,
        ),
      );
      final charlieCommittedKey = await waitForLatestKey(charlieRepo, 2);
      expect(charlieCommittedKey.encryptedKey, 'gek003-key-epoch-2');
      final repairedMessage = await waitForMessageStatus(
        charlieMsgRepo,
        bobMessageId,
        'delivered',
      );
      expect(repairedMessage.text, bobMessageText);
      expect(repairedMessage.id, bobMessageId);
      expect(repairedMessage.senderPeerId, bobPeerId);
      expect(repairedMessage.transportPeerId, bobDeviceId);
      expect(repairedMessage.keyGeneration, 2);
      expect(await charlieMsgRepo.getMessage(liveRepairId), isNull);
      final visibleAfterRepair = await charlieMsgRepo.getMessagesPage(groupId);
      expect(visibleAfterRepair, hasLength(1));
      expect(visibleAfterRepair.single.id, bobMessageId);

      final secondRetryCount = await charlieRepairRunner
          .retryPendingRepairsForKey(groupId: groupId, keyEpoch: 2);
      expect(secondRetryCount, 0);
      await drainGroupOfflineInbox(
        bridge: charlieBridge,
        groupRepo: charlieRepo,
        msgRepo: charlieMsgRepo,
        groupMessageListener: charlieMessageListener,
        pendingKeyRepairRepo: pendingRepo,
      );
      final visibleAfterDuplicateReplay = await charlieMsgRepo.getMessagesPage(
        groupId,
      );
      expect(visibleAfterDuplicateReplay, hasLength(1));
      expect(visibleAfterDuplicateReplay.single.id, bobMessageId);
    },
  );

  test(
    'GM-014 re-add send with delayed key queues explicit repair and catches up exactly once',
    () async {
      const groupId = 'group-1';
      const alicePeerId = 'peer-alice';
      const bobPeerId = 'peer-bob';
      const charliePeerId = 'peer-charlie';
      const postReaddMessageId = 'msg-gm014-alice-post-readd';
      const postReaddText = 'GM-014 Alice sends after Charlie re-add';
      const removedWindowText = 'GM-014 Alice during Charlie removal';
      final groupCreatedAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 5),
      );
      final readdAt = groupCreatedAt.add(const Duration(minutes: 2));
      final postReaddAt = readdAt.add(const Duration(seconds: 1));

      GroupMember member({
        required String peerId,
        required String username,
        required MemberRole role,
        required DateTime joinedAt,
      }) {
        return GroupMember(
          groupId: groupId,
          peerId: peerId,
          username: username,
          role: role,
          publicKey: 'pk-$peerId',
          mlKemPublicKey: 'mlkem-$peerId',
          joinedAt: joinedAt,
        );
      }

      String validKeyUpdateEnvelope({
        required int keyGeneration,
        required String encryptedKey,
      }) {
        final signedPayload = canonicalGroupKeyUpdateSignedPayload(
          groupId: groupId,
          sourcePeerId: alicePeerId,
          keyGeneration: keyGeneration,
          encryptedKey: encryptedKey,
        );
        final innerJson = jsonEncode({
          'groupId': groupId,
          'sourcePeerId': alicePeerId,
          'keyGeneration': keyGeneration,
          'encryptedKey': encryptedKey,
          'signatureAlgorithm': groupKeyUpdateSignatureAlgorithm,
          'signedPayload': signedPayload,
          'signature': 'fake-signature',
        });
        return jsonEncode({
          'encrypted': {
            'kem': 'fake-kem',
            'ciphertext': innerJson,
            'nonce': 'fake-nonce',
          },
        });
      }

      Future<GroupMessage> waitForMessageStatus(
        String messageId,
        String status,
      ) async {
        for (var attempt = 0; attempt < 30; attempt++) {
          final message = await msgRepo.getMessage(messageId);
          if (message?.status == status) {
            return message!;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        fail('Timed out waiting for $messageId status $status');
      }

      await groupRepo.updateGroup(
        testGroup.copyWith(createdAt: groupCreatedAt, createdBy: alicePeerId),
      );
      await groupRepo.saveMember(
        member(
          peerId: alicePeerId,
          username: 'Alice',
          role: MemberRole.admin,
          joinedAt: groupCreatedAt,
        ),
      );
      await groupRepo.saveMember(
        member(
          peerId: bobPeerId,
          username: 'Bob',
          role: MemberRole.writer,
          joinedAt: groupCreatedAt,
        ),
      );
      await groupRepo.saveMember(
        member(
          peerId: charliePeerId,
          username: 'Charlie',
          role: MemberRole.writer,
          joinedAt: readdAt,
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'gm014-key-epoch-1',
          createdAt: groupCreatedAt,
        ),
      );

      final pendingRepo = _InMemoryGroupPendingKeyRepairRepository();
      final repairRequests = <GroupKeyRepairRequest>[];
      final diagnostics = StreamController<Map<String, dynamic>>.broadcast();
      final liveMessages = StreamController<Map<String, dynamic>>.broadcast();
      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => charliePeerId,
        groupDiagnosticEvents: diagnostics.stream,
        pendingKeyRepairRepo: pendingRepo,
        requestGroupKeyRepair: repairRequests.add,
      );
      listener.start(liveMessages.stream);
      addTearDown(() async {
        listener.dispose();
        await diagnostics.close();
        await liveMessages.close();
      });

      final livePlaceholderFuture = listener.groupMessageStream.first.timeout(
        const Duration(seconds: 1),
      );
      diagnostics.add({
        'event': 'group:decryption_failed',
        'groupId': groupId,
        'senderId': alicePeerId,
        'keyEpoch': 2,
        'localKeyEpoch': 1,
        'error': 'missing epoch 2 key during GM-014 live delivery',
      });
      final livePlaceholder = await livePlaceholderFuture;
      expect(livePlaceholder.text, groupPendingKeyRepairPlaceholderText);
      expect(repairRequests.single.reason, groupKeyRepairReasonLiveDiagnostic);

      final replayEnvelope = await buildGroupOfflineReplayEnvelope(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        payloadType: groupOfflineReplayPayloadTypeMessage,
        plaintext: jsonEncode({
          'groupId': groupId,
          'senderId': alicePeerId,
          'senderUsername': 'Alice',
          'keyEpoch': 2,
          'text': postReaddText,
          'timestamp': postReaddAt.toIso8601String(),
          'messageId': postReaddMessageId,
        }),
        messageId: postReaddMessageId,
        senderPeerId: alicePeerId,
        senderPublicKey: 'pk-$alicePeerId',
        senderPrivateKey: 'sk-$alicePeerId',
        keyInfo: GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 2,
          encryptedKey: 'gm014-key-epoch-2',
          createdAt: readdAt,
        ),
        recipientPeerIds: const <String>[bobPeerId, charliePeerId],
      );
      bridge.addPage(groupId, '', [
        {'from': alicePeerId, 'message': replayEnvelope, 'timestamp': 2},
        {'from': alicePeerId, 'message': replayEnvelope, 'timestamp': 3},
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
        pendingKeyRepairRepo: pendingRepo,
        requestGroupKeyRepair: repairRequests.add,
      );

      final durablePlaceholder = await msgRepo.getMessage(postReaddMessageId);
      expect(durablePlaceholder, isNotNull);
      expect(durablePlaceholder!.status, groupPendingKeyRepairStatusPendingKey);
      expect(durablePlaceholder.text, groupPendingKeyRepairPlaceholderText);
      expect(durablePlaceholder.keyGeneration, 2);
      expect(await msgRepo.getMessage(livePlaceholder.id), isNull);
      expect(
        repairRequests.where(
          (request) => request.reason == groupKeyRepairReasonOfflineMissingKey,
        ),
        hasLength(1),
      );
      expect(repairRequests.last.messageId, postReaddMessageId);
      expect(
        (await msgRepo.getMessagesPage(
          groupId,
        )).where((message) => message.text == removedWindowText),
        isEmpty,
      );

      final repairRunner = GroupPendingKeyRepairRunner(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        pendingKeyRepairRepo: pendingRepo,
        replayGroupEnvelope: listener.handleReplayEnvelope,
      );
      final keyUpdates = StreamController<ChatMessage>.broadcast();
      final keyUpdateListener = GroupKeyUpdateListener(
        groupKeyUpdateStream: keyUpdates.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => 'mlkem-secret-charlie',
        getOwnPeerId: () async => charliePeerId,
        retryPendingGroupKeyRepairs: repairRunner.retryPendingRepairsForRequest,
      );
      keyUpdateListener.start();
      addTearDown(() async {
        keyUpdateListener.dispose();
        await keyUpdates.close();
      });

      keyUpdates.add(
        ChatMessage(
          from: alicePeerId,
          to: charliePeerId,
          content: validKeyUpdateEnvelope(
            keyGeneration: 2,
            encryptedKey: 'gm014-key-epoch-2',
          ),
          timestamp: readdAt.add(const Duration(seconds: 2)).toIso8601String(),
          isIncoming: true,
        ),
      );

      final repairedMessage = await waitForMessageStatus(
        postReaddMessageId,
        'delivered',
      );
      expect((await groupRepo.getLatestKey(groupId))!.keyGeneration, 2);
      expect(repairedMessage.text, postReaddText);
      expect(repairedMessage.senderPeerId, alicePeerId);
      expect(repairedMessage.keyGeneration, 2);
      expect(repairedMessage.timestamp, postReaddAt);
      expect(await msgRepo.getMessage(livePlaceholder.id), isNull);
      final visibleMessages = await msgRepo.getMessagesPage(groupId);
      expect(
        visibleMessages.where((message) => message.id == postReaddMessageId),
        hasLength(1),
      );
      expect(
        visibleMessages.where((message) => message.text == removedWindowText),
        isEmpty,
      );
      final pendingRepairs = await pendingRepo.getPendingRepairsForGroupEpoch(
        groupId: groupId,
        keyEpoch: 2,
      );
      expect(pendingRepairs, isEmpty);
      expect(
        pendingRepo.repairs.values.where(
          (repair) =>
              repair.messageId == postReaddMessageId &&
              repair.status == groupPendingKeyRepairStatusRepaired,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'GK-022 removed member with old key cannot decrypt post-removal inbox replay',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-self',
          username: 'Removed',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'replay-key-epoch-1',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      expect(await groupRepo.getKeyByGeneration('group-1', 1), isNotNull);
      expect(await groupRepo.getKeyByGeneration('group-1', 2), isNull);

      const protectedText = 'GK-022 post-removal plaintext';
      final postRemovalReplay = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        keyGeneration: 2,
        plaintext: jsonEncode({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 2,
          'text': protectedText,
          'timestamp': '2026-05-12T15:22:00.000Z',
          'messageId': 'msg-gk022-post-removal',
        }),
        messageId: 'msg-gk022-post-removal',
      );
      bridge.addPage('group-1', '', [
        {'from': 'peer-sender', 'message': postRemovalReplay, 'timestamp': 2},
      ], '');

      final output = <String>[];
      final previousLogging = flowEventLoggingEnabled;
      final originalDebugPrint = debugPrint;
      flowEventLoggingEnabled = true;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) output.add(message);
      };
      addTearDown(() {
        debugPrint = originalDebugPrint;
        flowEventLoggingEnabled = previousLogging;
      });

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      expect(await groupRepo.getKeyByGeneration('group-1', 1), isNotNull);
      expect(await groupRepo.getKeyByGeneration('group-1', 2), isNull);
      expect(bridge.commandLog, contains('payload.verify'));
      expect(bridge.commandLog, isNot(contains('group.decrypt')));

      final placeholder = await msgRepo.getMessage('msg-gk022-post-removal');
      expect(placeholder, isNotNull);
      expect(placeholder!.text, groupUndecryptablePlaceholderText);
      expect(placeholder.text, isNot(contains(protectedText)));
      expect(placeholder.senderPeerId, 'peer-sender');
      expect(placeholder.keyGeneration, 2);
      expect(placeholder.status, 'undecryptable');
      expect(placeholder.isIncoming, isTrue);
      expect(msgRepo.count, 1);

      final visibleMessages = await msgRepo.getMessagesPage('group-1');
      expect(
        visibleMessages.where(
          (message) => message.text.contains(protectedText),
        ),
        isEmpty,
      );

      final events = output
          .where((line) => line.startsWith('[FLOW] '))
          .map(
            (line) =>
                jsonDecode(line.substring('[FLOW] '.length))
                    as Map<String, dynamic>,
          )
          .toList();
      final skipped = events.firstWhere(
        (event) => event['event'] == 'GROUP_DRAIN_OFFLINE_INBOX_DECODE_SKIPPED',
      );
      expect(skipped['details']['error'], contains('Missing group replay key'));
      expect(skipped['details']['error'], contains('epoch 2'));
      expect(skipped['details']['placeholderSaved'], isTrue);
      expect(
        events,
        contains(
          isA<Map<String, dynamic>>().having(
            (event) => event['event'],
            'event',
            'GROUP_DRAIN_OFFLINE_INBOX_UNDECRYPTABLE_PLACEHOLDER_SAVED',
          ),
        ),
      );
    },
  );

  test(
    'future epoch encrypted replay creates one undecryptable placeholder without decrypting',
    () async {
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'replay-key-1',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      final futureEpochKey = GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 2,
        encryptedKey: 'replay-key-2',
        createdAt: DateTime.now().toUtc(),
      );
      final futureReplay = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        keyGeneration: futureEpochKey.keyGeneration,
        plaintext: jsonEncode({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 2,
          'text': 'Future epoch replay',
          'timestamp': '2026-04-29T10:02:00.000Z',
          'messageId': 'msg-ms018-future-epoch',
        }),
        messageId: 'msg-ms018-future-epoch',
      );
      bridge.addPage('group-1', '', [
        {'from': 'peer-sender', 'message': futureReplay, 'timestamp': 2},
        {'from': 'peer-sender', 'message': futureReplay, 'timestamp': 3},
      ], '');

      final output = <String>[];
      final previousLogging = flowEventLoggingEnabled;
      final originalDebugPrint = debugPrint;
      flowEventLoggingEnabled = true;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) output.add(message);
      };
      addTearDown(() {
        debugPrint = originalDebugPrint;
        flowEventLoggingEnabled = previousLogging;
      });

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      final placeholder = await msgRepo.getMessage('msg-ms018-future-epoch');
      expect(placeholder, isNotNull);
      expect(placeholder!.text, groupUndecryptablePlaceholderText);
      expect(placeholder.text, isNot(contains('Future epoch replay')));
      expect(placeholder.senderPeerId, 'peer-sender');
      expect(placeholder.keyGeneration, 2);
      expect(placeholder.status, 'undecryptable');
      expect(placeholder.isIncoming, isTrue);
      expect(msgRepo.count, 1);
      expect(bridge.commandLog, isNot(contains('group.decrypt')));

      final events = output
          .where((line) => line.startsWith('[FLOW] '))
          .map(
            (line) =>
                jsonDecode(line.substring('[FLOW] '.length))
                    as Map<String, dynamic>,
          )
          .toList();
      final skipped = events.firstWhere(
        (event) => event['event'] == 'GROUP_DRAIN_OFFLINE_INBOX_DECODE_SKIPPED',
      );
      expect(skipped['details']['error'], contains('Missing group replay key'));
      expect(skipped['details']['error'], contains('epoch 2'));
      expect(skipped['details']['placeholderSaved'], isTrue);
      expect(
        events,
        contains(
          isA<Map<String, dynamic>>().having(
            (event) => event['event'],
            'event',
            'GROUP_DRAIN_OFFLINE_INBOX_UNDECRYPTABLE_PLACEHOLDER_SAVED',
          ),
        ),
      );
    },
  );

  test(
    'MD-011 removed member cannot decode future media replay with only the old epoch',
    () async {
      final mediaRepo = InMemoryMediaAttachmentRepository();
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-removed',
          username: 'Removed',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'replay-key-epoch-1',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      final futureEpochKey = GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 2,
        encryptedKey: 'replay-key-epoch-2',
        createdAt: DateTime.now().toUtc(),
      );
      final futureReplay = await signedReplayEnvelope(
        payloadType: groupOfflineReplayPayloadTypeMessage,
        keyGeneration: futureEpochKey.keyGeneration,
        plaintext: jsonEncode({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 2,
          'text': 'MD-011 future media replay',
          'timestamp': '2026-04-29T12:00:00.000Z',
          'messageId': 'msg-md011-future-media-replay',
          'media': [
            {
              'id': 'blob-md011-future-replay',
              'mime': 'image/jpeg',
              'size': 4,
              'mediaType': 'image',
              'downloadStatus': 'pending',
              'contentHash': _validContentHash,
              'encryptionKeyBase64': 'key-md011-future-replay',
              'encryptionNonce': 'nonce-md011-future-replay',
              'encryptionScheme': 'blob_aes_256_gcm_v1',
              'createdAt': '2026-04-29T12:00:00.000Z',
            },
          ],
        }),
        messageId: 'msg-md011-future-media-replay',
      );
      bridge.addPage('group-1', '', [
        {'from': 'peer-sender', 'message': futureReplay, 'timestamp': 2},
      ], '');

      final output = <String>[];
      final previousLogging = flowEventLoggingEnabled;
      final originalDebugPrint = debugPrint;
      flowEventLoggingEnabled = true;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) output.add(message);
      };
      addTearDown(() {
        debugPrint = originalDebugPrint;
        flowEventLoggingEnabled = previousLogging;
      });

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        mediaAttachmentRepo: mediaRepo,
      );

      final placeholder = await msgRepo.getMessage(
        'msg-md011-future-media-replay',
      );
      expect(placeholder, isNotNull);
      expect(placeholder!.text, groupUndecryptablePlaceholderText);
      expect(placeholder.text, isNot(contains('MD-011 future media replay')));
      expect(placeholder.keyGeneration, 2);
      expect(placeholder.status, 'undecryptable');
      expect(msgRepo.count, 1);
      expect(mediaRepo.count, 0);
      expect(await mediaRepo.getPendingDownloads(), isEmpty);
      expect(bridge.commandLog, contains('group:inboxRetrieveCursor'));
      expect(bridge.commandLog, isNot(contains('group.decrypt')));
      expect(bridge.commandLog, isNot(contains('media:download')));
      expect(bridge.commandLog, isNot(contains('blob:decrypt')));

      final events = output
          .where((line) => line.startsWith('[FLOW] '))
          .map(
            (line) =>
                jsonDecode(line.substring('[FLOW] '.length))
                    as Map<String, dynamic>,
          )
          .toList();
      final skipped = events.firstWhere(
        (event) => event['event'] == 'GROUP_DRAIN_OFFLINE_INBOX_DECODE_SKIPPED',
      );
      expect(skipped['details']['error'], contains('Missing group replay key'));
      expect(skipped['details']['error'], contains('epoch 2'));
    },
  );

  // ---------------------------------------------------------------------------
  // Reaction drain tests
  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
  // Phase 6: Cursor continuation and exactly-once delivery
  // ---------------------------------------------------------------------------

  group('drainGroupOfflineInbox use case', () {
    test(
      'resume uses cursor continuation rather than timestamp guessing',
      () async {
        final ts = DateTime.now().toUtc().toIso8601String();

        // Page 1 returns cursor "page2", page 2 returns cursor ""
        bridge.addPage('group-1', '', [
          {
            'groupId': 'group-1',
            'senderId': 'peer-sender',
            'senderUsername': 'Sender',
            'keyEpoch': 1,
            'text': 'Page 1 message',
            'timestamp': ts,
            'messageId': 'msg-p6-p1',
          },
        ], 'page2');

        bridge.addPage('group-1', 'page2', [
          {
            'groupId': 'group-1',
            'senderId': 'peer-sender',
            'senderUsername': 'Sender',
            'keyEpoch': 1,
            'text': 'Page 2 message',
            'timestamp': ts,
            'messageId': 'msg-p6-p2',
          },
        ], '');

        await drainGroupOfflineInbox(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
        );

        // Verify that the bridge was called with cursor="page2" for the second page
        // and NOT with a sinceTimestamp
        final cursorCmds = bridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .where((m) => m['cmd'] == 'group:inboxRetrieveCursor')
            .toList();

        expect(cursorCmds.length, 2);
        expect(cursorCmds[0]['payload']['cursor'], '');
        expect(cursorCmds[1]['payload']['cursor'], 'page2');

        // Verify no sinceTimestamp field was sent
        for (final cmd in cursorCmds) {
          expect(
            cmd['payload'].containsKey('sinceTimestamp'),
            isFalse,
            reason: 'Cursor-based pagination should not use sinceTimestamp',
          );
        }

        expect(msgRepo.count, 2);
      },
    );

    test(
      'GI-017 offline member drains 120 entitled messages across pages exactly once',
      () async {
        await saveDefaultReplayKey();

        final startedAt = DateTime.utc(2026, 5, 8, 10);
        final relayMessages = <Map<String, dynamic>>[];
        for (var i = 0; i < 120; i++) {
          final id = 'gi017-msg-${i.toString().padLeft(3, '0')}';
          relayMessages.add(
            await signedRelayMessage(
              id: id,
              text: 'GI-017 replay message $i',
              timestamp: startedAt.add(Duration(seconds: i)),
            ),
          );
        }

        bridge.addPage(
          'group-1',
          '',
          relayMessages.sublist(0, 50),
          'cursor-050',
        );
        bridge.addPage(
          'group-1',
          'cursor-050',
          relayMessages.sublist(50, 100),
          'cursor-100',
        );
        bridge.addPage('group-1', 'cursor-100', relayMessages.sublist(100), '');

        await drainGroupOfflineInbox(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          selfPeerId: 'peer-local',
          retentionNowUtc: _fixedDateFixtureRetentionNow,
        );

        final cursorCmds = bridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .where((m) => m['cmd'] == 'group:inboxRetrieveCursor')
            .toList();
        expect(cursorCmds, hasLength(3));
        expect(cursorCmds.map((cmd) => cmd['payload']['cursor']).toList(), [
          '',
          'cursor-050',
          'cursor-100',
        ]);
        for (final cmd in cursorCmds) {
          final payload = cmd['payload'] as Map<String, dynamic>;
          expect(payload['limit'], 50);
          expect(payload.containsKey('sinceTimestamp'), isFalse);
        }

        expect(await msgRepo.getMessageCount('group-1'), 120);
        expect(await msgRepo.getInboxCursor('group-1'), '');

        final stored = await msgRepo.getMessagesPage('group-1', limit: 200);
        expect(stored, hasLength(120));
        final seenIds = <String>{};
        for (var i = 0; i < stored.length; i++) {
          final expectedId = 'gi017-msg-${i.toString().padLeft(3, '0')}';
          expect(stored[i].id, expectedId);
          expect(stored[i].text, 'GI-017 replay message $i');
          expect(seenIds.add(stored[i].id), isTrue);
        }

        await drainGroupOfflineInbox(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          selfPeerId: 'peer-local',
          retentionNowUtc: _fixedDateFixtureRetentionNow,
        );
        expect(await msgRepo.getMessageCount('group-1'), 120);
      },
    );

    test('watchdog restart drains missed group messages exactly once', () async {
      final ts = DateTime.now().toUtc().toIso8601String();

      bridge.addPage('group-1', '', [
        {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 1,
          'text': 'Watchdog missed msg',
          'timestamp': ts,
          'messageId': 'msg-wd-once',
        },
      ], '');

      // Drain the inbox
      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      // Verify messages are saved to msgRepo exactly once
      expect(msgRepo.count, 1);

      // Drain again with the same page data (bridge still returns same message)
      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      // Verify count hasn't changed (dedup by messageId)
      expect(
        msgRepo.count,
        1,
        reason: 'Draining twice should not duplicate messages',
      );
    });

    test(
      'first group inbox page returns before background continuation completes',
      () async {
        final ts = DateTime.now().toUtc().toIso8601String();

        // Page 1 with cursor pointing to page 2
        bridge.addPage('group-1', '', [
          {
            'groupId': 'group-1',
            'senderId': 'peer-sender',
            'senderUsername': 'Sender',
            'keyEpoch': 1,
            'text': 'First page only',
            'timestamp': ts,
            'messageId': 'msg-fp-1',
          },
        ], 'more-pages-cursor');

        // Page 2 (should not be fetched)
        bridge.addPage('group-1', 'more-pages-cursor', [
          {
            'groupId': 'group-1',
            'senderId': 'peer-sender',
            'senderUsername': 'Sender',
            'keyEpoch': 1,
            'text': 'Second page',
            'timestamp': ts,
            'messageId': 'msg-fp-2',
          },
        ], '');

        // Call drainGroupOfflineInbox with drainAllPages: false
        await drainGroupOfflineInbox(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          drainAllPages: false,
        );

        // Verify that only the first page is fetched
        expect(msgRepo.count, 1);

        // Bridge should have been called exactly once with cursor=""
        final cursorCmds = bridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .where((m) => m['cmd'] == 'group:inboxRetrieveCursor')
            .toList();

        expect(
          cursorCmds.length,
          1,
          reason: 'Only one page should be fetched when drainAllPages=false',
        );
        expect(cursorCmds[0]['payload']['cursor'], '');
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Reaction drain tests
  // ---------------------------------------------------------------------------
  test('drains group_reaction items when reactionRepo is provided', () async {
    final reactionRepo = FakeReactionRepository();

    final innerReaction = jsonEncode({
      'id': 'rxn-1',
      'messageId': 'msg-1',
      'emoji': '\u{1F44D}',
      'action': 'add',
      'senderPeerId': 'peer-sender',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    final inboxMessage = jsonEncode({
      'type': 'group_reaction',
      'senderId': 'peer-sender',
      'reaction': innerReaction,
    });

    bridge.addPage('group-1', '', [
      {'from': 'peer-sender', 'message': inboxMessage, 'timestamp': 123},
    ], '');

    await drainGroupOfflineInbox(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
    );

    // Reaction should be persisted.
    expect(reactionRepo.saveReactionCallCount, 1);
    // Should NOT be saved as a regular message.
    expect(msgRepo.count, 0);
  });

  test(
    'ignores replayed group_reaction items with mismatched sender identity',
    () async {
      final reactionRepo = FakeReactionRepository();

      final innerReaction = jsonEncode({
        'id': 'rxn-mismatch-1',
        'messageId': 'msg-mismatch-1',
        'emoji': '\u{1F44D}',
        'action': 'add',
        'senderPeerId': 'peer-other',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      final inboxMessage = jsonEncode({
        'type': 'group_reaction',
        'senderId': 'peer-sender',
        'reaction': innerReaction,
      });

      bridge.addPage('group-1', '', [
        {'from': 'peer-sender', 'message': inboxMessage, 'timestamp': 123},
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
      );

      expect(reactionRepo.saveReactionCallCount, 0);
      expect(
        await reactionRepo.getReactionsForMessage('msg-mismatch-1'),
        isEmpty,
      );
      expect(msgRepo.count, 0);
    },
  );

  test(
    'replayed system messages trust the outer sender over payload sender',
    () async {
      final listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final inboxMessage = jsonEncode({
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'text': jsonEncode({
          '__sys': 'group_dissolved',
          'dissolvedAt': '2026-04-05T12:00:00.000Z',
          'dissolvedBy': 'peer-admin',
        }),
        'timestamp': '2026-04-05T12:00:00.000Z',
      });

      bridge.addPage('group-1', '', [
        {'from': 'peer-sender', 'message': inboxMessage, 'timestamp': 123},
      ], '');

      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupMessageListener: listener,
      );

      final group = await groupRepo.getGroup('group-1');
      expect(group, isNotNull);
      expect(group!.isDissolved, isFalse);
      expect(await msgRepo.getLatestMessage('group-1'), isNull);
      expect(bridge.commandLog, isNot(contains('group:leave')));
    },
  );
}
