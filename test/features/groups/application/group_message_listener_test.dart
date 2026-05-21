import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show DebugPrintCallback, debugPrint;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_repair.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';

const _validContentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _bytes123ContentHash =
    '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81';

class SequencedUpdateConfigBridge extends FakeBridge {
  SequencedUpdateConfigBridge(this._behaviors);

  final List<Future<String> Function(String message)> _behaviors;
  int _updateConfigCallIndex = 0;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:updateConfig' &&
        _updateConfigCallIndex < _behaviors.length) {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      return _behaviors[_updateConfigCallIndex++](message);
    }

    return super.send(message);
  }
}

class _DelayedGroupLeaveBridge extends FakeBridge {
  final Completer<void> leaveStarted = Completer<void>();
  final Completer<void> _releaseLeave = Completer<void>();
  int joinCalls = 0;

  void completeLeave() {
    if (!_releaseLeave.isCompleted) {
      _releaseLeave.complete();
    }
  }

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:leave') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      if (!leaveStarted.isCompleted) {
        leaveStarted.complete();
      }
      await _releaseLeave.future;
      return jsonEncode({'ok': true});
    }
    if (cmd == 'group:join') {
      joinCalls++;
    }
    return super.send(message);
  }
}

class GateableMediaAttachmentRepository
    extends InMemoryMediaAttachmentRepository {
  final Completer<void> firstDownloadingGate = Completer<void>();
  int downloadingUpdateCalls = 0;
  bool _gatedFirstDownloadingUpdate = false;

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {
    if (downloadStatus == 'downloading') {
      downloadingUpdateCalls++;
      if (!_gatedFirstDownloadingUpdate) {
        _gatedFirstDownloadingUpdate = true;
        await firstDownloadingGate.future;
      }
    }
    await super.updateDownloadStatus(id, downloadStatus);
  }
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
        .toList();
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

class _TrackingInviteDeliveryAttemptRepository
    implements GroupInviteDeliveryAttemptRepository {
  final Map<String, GroupInviteDeliveryAttempt> attempts = {};

  String _key(String groupId, String peerId) => '$groupId::$peerId';

  @override
  Future<void> saveAttempt(GroupInviteDeliveryAttempt attempt) async {
    attempts[_key(attempt.groupId, attempt.peerId)] = attempt;
  }

  @override
  Future<GroupInviteDeliveryAttempt?> getAttempt({
    required String groupId,
    required String peerId,
  }) async {
    return attempts[_key(groupId, peerId)];
  }

  @override
  Future<List<GroupInviteDeliveryAttempt>> getAttemptsForGroup(
    String groupId,
  ) async {
    return attempts.values
        .where((attempt) => attempt.groupId == groupId)
        .toList(growable: false);
  }

  @override
  Future<GroupInviteDeliveryStatus> getStatusForMember({
    required String groupId,
    required String peerId,
  }) async {
    return attempts[_key(groupId, peerId)]?.status ??
        GroupInviteDeliveryStatus.unknown;
  }

  @override
  Future<Map<String, GroupInviteDeliveryStatus>> getStatusesForGroupMembers(
    String groupId,
  ) async {
    return {
      for (final attempt in attempts.values.where((a) => a.groupId == groupId))
        attempt.peerId: attempt.status,
    };
  }

  @override
  Future<void> updateStatus({
    required String groupId,
    required String peerId,
    required GroupInviteDeliveryStatus status,
    DateTime? updatedAt,
  }) async {
    final existing = attempts[_key(groupId, peerId)];
    final now = updatedAt ?? DateTime.now().toUtc();
    attempts[_key(groupId, peerId)] =
        existing?.copyWith(
          status: status,
          updatedAt: now,
          clearLastError: true,
        ) ??
        GroupInviteDeliveryAttempt(
          groupId: groupId,
          peerId: peerId,
          status: status,
          attemptedAt: now,
          updatedAt: now,
        );
  }

  @override
  Future<void> markJoined({
    required String groupId,
    required String peerId,
    String? username,
    DateTime? joinedAt,
  }) async {
    final now = joinedAt ?? DateTime.now().toUtc();
    final existing = attempts[_key(groupId, peerId)];
    attempts[_key(groupId, peerId)] =
        existing?.copyWith(
          username: username,
          status: GroupInviteDeliveryStatus.joined,
          updatedAt: now,
          clearLastError: true,
        ) ??
        GroupInviteDeliveryAttempt(
          groupId: groupId,
          peerId: peerId,
          username: username,
          status: GroupInviteDeliveryStatus.joined,
          attemptedAt: now,
          updatedAt: now,
        );
  }

  @override
  Future<int> deleteAttempt({
    required String groupId,
    required String peerId,
  }) async {
    return attempts.remove(_key(groupId, peerId)) == null ? 0 : 1;
  }

  @override
  Future<int> deleteAttemptsForGroup(String groupId) async {
    final before = attempts.length;
    attempts.removeWhere((_, attempt) => attempt.groupId == groupId);
    return before - attempts.length;
  }
}

class _FakeEventLog {
  final entries = <Map<String, Object?>>[];
  final _payloadBySourceEventId = <String, String>{};

  Future<Map<String, Object?>> append({
    required String groupId,
    required String eventType,
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> payload,
    DateTime? createdAt,
  }) async {
    final canonical = canonicalizeGroupEventLogPayload(payload);
    final existing = _payloadBySourceEventId[sourceEventId];
    if (existing != null && existing != canonical) {
      throw GroupEventLogTamperException('conflicting replay');
    }
    _payloadBySourceEventId[sourceEventId] = canonical;
    final entry = {
      'groupId': groupId,
      'eventType': eventType,
      'sourcePeerId': sourcePeerId,
      'sourceEventId': sourceEventId,
      'sourceTimestamp': sourceTimestamp,
      'payload': payload,
    };
    if (existing == null) {
      entries.add(entry);
    }
    return entry;
  }
}

class _DelayedMediaDownloadBridge extends FakeBridge {
  final Completer<void> downloadGate = Completer<void>();

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'media:download') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      await downloadGate.future;
      final payload =
          parsed['payload'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final outputPath = payload['outputPath'] as String?;
      if (outputPath != null) {
        final file = File(outputPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(const <int>[1, 2, 3]);
      }
      return jsonEncode({'ok': true});
    }

    return super.send(message);
  }
}

void main() {
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;
  late FakeBridge bridge;
  late GroupMessageListener listener;
  late StreamController<Map<String, dynamic>> sourceController;
  late DebugPrintCallback originalDebugPrint;
  late List<String> debugLogs;
  final initialGroupCreatedAt = DateTime.utc(2026, 4, 5, 11, 59, 0);
  final initialMemberJoinedAt = DateTime.utc(2026, 4, 5, 11, 59, 30);

  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'group-topic-1',
    createdAt: initialGroupCreatedAt,
    createdBy: 'peer-admin',
    myRole: GroupRole.admin,
  );

  Future<void> saveTrustedAdminMember({
    String groupId = 'group-1',
    String peerId = 'peer-admin',
    String username = 'Admin',
    String publicKey = 'pk-admin',
  }) {
    return groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: peerId,
        username: username,
        role: MemberRole.admin,
        publicKey: publicKey,
        joinedAt: initialMemberJoinedAt,
      ),
    );
  }

  Map<String, dynamic> buildMetadataConfig({
    required DateTime updatedAt,
    String name = 'Renamed Group',
    String? description = 'Fresh description',
    String? avatarBlobId,
    String? avatarMime,
  }) {
    return buildGroupConfigPayload(
      testGroup.copyWith(
        name: name,
        description: description,
        avatarBlobId: avatarBlobId,
        avatarMime: avatarMime,
        lastMetadataEventAt: updatedAt,
      ),
      [
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          publicKey: 'pk-admin',
          joinedAt: initialGroupCreatedAt,
        ),
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-sender',
          username: 'Sender',
          role: MemberRole.writer,
          publicKey: 'pk-sender',
          joinedAt: initialMemberJoinedAt,
        ),
      ],
    );
  }

  Map<String, dynamic> signedMetadataSystemPayload({
    required DateTime updatedAt,
    required Map<String, dynamic> groupConfig,
    String groupId = 'group-1',
    String actorPeerId = 'peer-admin',
    String actorUsername = 'Admin',
    String actorPublicKey = 'pk-admin',
    String signature = 'sig-metadata',
    Map<String, dynamic>? signedGroupConfig,
    String? signedUpdatedAt,
    String? signatureAlgorithm = 'ed25519',
  }) {
    final effectiveSignedConfig = signedGroupConfig ?? groupConfig;
    final actorPayload = {
      'schemaVersion': 1,
      'eventType': 'group_metadata_updated',
      'groupId': groupId,
      'updatedAt': signedUpdatedAt ?? updatedAt.toUtc().toIso8601String(),
      'actor': {
        'peerId': actorPeerId,
        'username': actorUsername,
        'publicKey': actorPublicKey,
      },
      'groupConfigVersion': effectiveSignedConfig[groupConfigVersionField],
      'groupConfigStateHash': effectiveSignedConfig[groupConfigStateHashField],
      'groupConfig': effectiveSignedConfig,
    };
    return {
      '__sys': 'group_metadata_updated',
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'groupConfig': groupConfig,
      'actorEvent': {
        'signedPayload': canonicalizeGroupEventLogPayload(actorPayload),
        'signature': signature,
        'signatureAlgorithm': signatureAlgorithm,
      },
    };
  }

  Future<Map<String, dynamic>> signedAuditSystemPayload({
    required String transitionType,
    required String sourceEventId,
    required DateTime eventAt,
    required Map<String, dynamic> systemPayload,
    String actorPeerId = 'peer-admin',
    String actorUsername = 'Admin',
    String actorPublicKey = 'pk-admin',
  }) {
    return signGroupSystemTransitionPayload(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: 'group-1',
      transitionType: transitionType,
      sourceEventId: sourceEventId,
      eventAt: eventAt,
      actorPeerId: actorPeerId,
      actorUsername: actorUsername,
      actorSigningPublicKey: actorPublicKey,
      actorPrivateKey: 'sk-$actorPeerId',
      systemPayload: systemPayload,
    );
  }

  Future<void> expectNotificationCount(
    FakeNotificationService service,
    int count,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (service.shown.length < count && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(service.shown, hasLength(count));
  }

  setUp(() async {
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();
    bridge = FakeBridge();
    sourceController = StreamController<Map<String, dynamic>>.broadcast();
    debugLogs = <String>[];
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        debugLogs.add(message);
      }
    };

    await groupRepo.saveGroup(testGroup);
    await saveTrustedAdminMember();
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-sender',
        username: 'Sender',
        role: MemberRole.writer,
        joinedAt: initialMemberJoinedAt,
      ),
    );

    listener = GroupMessageListener(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      bridge: bridge,
    );
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
    listener.dispose();
    sourceController.close();
  });

  test(
    'UP-013 persists incoming group message without UI stream subscriber',
    () async {
      listener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'UP-013 delivered while route is away',
        'timestamp': DateTime.utc(2026, 5, 14, 1).toIso8601String(),
        'messageId': 'up013-route-away-listener',
      });

      await Future.delayed(const Duration(milliseconds: 50));

      final saved = await msgRepo.getMessage('up013-route-away-listener');
      expect(saved, isNotNull);
      expect(saved!.groupId, 'group-1');
      expect(saved.text, 'UP-013 delivered while route is away');
      expect(saved.isIncoming, isTrue);
      expect(saved.status, 'delivered');
      expect(await msgRepo.getUnreadCount('group-1'), 1);
    },
  );

  test(
    'GO-004 live decryption failure creates repair placeholder and trigger without plaintext delivery',
    () async {
      final diagnostics = StreamController<Map<String, dynamic>>.broadcast();
      final pendingRepo = _InMemoryGroupPendingKeyRepairRepository();
      final repairRequests = <GroupKeyRepairRequest>[];
      listener.dispose();
      listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        groupDiagnosticEvents: diagnostics.stream,
        pendingKeyRepairRepo: pendingRepo,
        requestGroupKeyRepair: (request) {
          repairRequests.add(request);
        },
      );
      listener.start(sourceController.stream);
      addTearDown(diagnostics.close);

      final emittedMessage = listener.groupMessageStream.first.timeout(
        const Duration(seconds: 1),
      );
      diagnostics.add({
        'event': 'group:decryption_failed',
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'keyEpoch': 3,
        'localKeyEpoch': 2,
        'error': 'cipher: message authentication failed',
        'plaintext': 'GO-004 plaintext must not render',
        'groupKey': 'GO-004 group key must not persist',
        'ciphertext': 'GO-004 ciphertext must not persist',
        'nonce': 'GO-004 nonce must not persist',
      });

      final placeholder = await emittedMessage;
      expect(placeholder.groupId, 'group-1');
      expect(placeholder.senderPeerId, 'peer-sender');
      expect(placeholder.text, groupPendingKeyRepairPlaceholderText);
      expect(placeholder.text, isNot(contains('GO-004 plaintext')));
      expect(placeholder.text, isNot(contains('GO-004 group key')));
      expect(placeholder.text, isNot(contains('GO-004 ciphertext')));
      expect(placeholder.status, groupPendingKeyRepairStatusPendingKey);
      expect(placeholder.keyGeneration, 3);
      expect(await msgRepo.getMessage(placeholder.id), isNotNull);
      expect(msgRepo.count, 1);
      expect(pendingRepo.repairs.values, hasLength(1));
      final repair = pendingRepo.repairs.values.single;
      expect(repair.senderPeerId, 'peer-sender');
      expect(repair.keyEpoch, 3);
      expect(repair.lastError, 'cipher: message authentication failed');
      expect(repair.lastError, isNot(contains('GO-004 plaintext')));
      expect(repair.lastError, isNot(contains('GO-004 group key')));
      expect(repair.lastError, isNot(contains('GO-004 ciphertext')));
      expect(repair.replayEnvelopeJson, isNull);
      expect(repairRequests, hasLength(1));
      expect(repairRequests.single.groupId, 'group-1');
      expect(repairRequests.single.keyEpoch, 3);
      expect(repairRequests.single.reason, groupKeyRepairReasonLiveDiagnostic);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 3,
        'messageId': 'normal-live-after-diagnostic',
        'text': 'Normal live delivery is separate',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });
      await Future<void>.delayed(Duration.zero);

      expect(
        await msgRepo.getMessage('normal-live-after-diagnostic'),
        isNotNull,
      );
      expect(msgRepo.count, 2);
    },
  );

  test(
    'DE-014 decryption failure queues repair placeholder and later valid event still persists',
    () async {
      final diagnostics = StreamController<Map<String, dynamic>>.broadcast();
      final pendingRepo = _InMemoryGroupPendingKeyRepairRepository();
      final repairRequests = <GroupKeyRepairRequest>[];
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      listener.dispose();
      listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        groupDiagnosticEvents: diagnostics.stream,
        pendingKeyRepairRepo: pendingRepo,
        requestGroupKeyRepair: repairRequests.add,
      );
      listener.start(sourceController.stream);
      addTearDown(diagnostics.close);

      final placeholderFuture = listener.groupMessageStream.first.timeout(
        const Duration(seconds: 1),
      );
      diagnostics.add({
        'event': 'group:decryption_failed',
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'keyEpoch': 4,
        'localKeyEpoch': 1,
        'error': 'cipher failed secret-key-material should stay out of flow',
      });

      final placeholder = await placeholderFuture;
      final repairId = liveGroupPendingKeyRepairId(
        groupId: 'group-1',
        senderPeerId: 'peer-sender',
        keyEpoch: 4,
        localKeyEpoch: 1,
      );
      expect(placeholder.id, repairId);
      expect(placeholder.text, groupPendingKeyRepairPlaceholderText);
      expect(placeholder.status, groupPendingKeyRepairStatusPendingKey);
      expect(placeholder.keyGeneration, 4);
      expect(await msgRepo.getMessage(repairId), isNotNull);
      expect(msgRepo.count, 1);
      expect(pendingRepo.repairs.values, hasLength(1));
      expect(pendingRepo.repairs.values.single.replayEnvelopeJson, isNull);
      expect(repairRequests, hasLength(1));
      expect(repairRequests.single.reason, groupKeyRepairReasonLiveDiagnostic);
      final encodedFlowEvents = jsonEncode(flowEvents);
      expect(encodedFlowEvents, contains('GROUP_LIVE_DECRYPTION_REPAIR'));
      expect(encodedFlowEvents, isNot(contains('secret-key-material')));

      final laterEvent = listener.groupMessageStream
          .where((message) => message.id == 'de014-valid-after-diagnostic')
          .first
          .timeout(const Duration(seconds: 1));
      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 4,
        'messageId': 'de014-valid-after-diagnostic',
        'text': 'DE-014 later live delivery still arrives',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      final laterMessage = await laterEvent;
      expect(laterMessage.text, 'DE-014 later live delivery still arrives');
      expect(
        await msgRepo.getMessage('de014-valid-after-diagnostic'),
        isNotNull,
      );
      expect(msgRepo.count, 2);
    },
  );

  test(
    'SV-005 tampered envelope diagnostic does not poison later listener delivery',
    () async {
      final diagnostics = StreamController<Map<String, dynamic>>.broadcast();
      final pendingRepo = _InMemoryGroupPendingKeyRepairRepository();
      final repairRequests = <GroupKeyRepairRequest>[];

      listener.dispose();
      listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        groupDiagnosticEvents: diagnostics.stream,
        pendingKeyRepairRepo: pendingRepo,
        requestGroupKeyRepair: repairRequests.add,
      );
      listener.start(sourceController.stream);
      addTearDown(diagnostics.close);

      final placeholderFuture = listener.groupMessageStream.first.timeout(
        const Duration(seconds: 1),
      );
      diagnostics.add({
        'event': 'group:decryption_failed',
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'keyEpoch': 5,
        'localKeyEpoch': 5,
        'error': 'cipher: message authentication failed after tamper',
      });

      final placeholder = await placeholderFuture;
      expect(placeholder.text, groupPendingKeyRepairPlaceholderText);
      expect(placeholder.status, groupPendingKeyRepairStatusPendingKey);
      expect(placeholder.keyGeneration, 5);
      expect(msgRepo.count, 1);
      expect(pendingRepo.repairs.values, hasLength(1));
      expect(repairRequests, hasLength(1));
      expect(await msgRepo.getMessage('sv005-valid-after-tamper'), isNull);

      final laterEvent = listener.groupMessageStream
          .where((message) => message.id == 'sv005-valid-after-tamper')
          .first
          .timeout(const Duration(seconds: 1));
      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 5,
        'messageId': 'sv005-valid-after-tamper',
        'text': 'SV-005 valid listener delivery after tamper',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      final laterMessage = await laterEvent;
      expect(laterMessage.text, 'SV-005 valid listener delivery after tamper');
      expect(await msgRepo.getMessage('sv005-valid-after-tamper'), isNotNull);
      expect(msgRepo.count, 2);
    },
  );

  test(
    'GO-003 sender-visible validation feedback marks outgoing row failed and retryable',
    () async {
      final diagnostics = StreamController<Map<String, dynamic>>.broadcast();
      listener.dispose();
      listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        groupDiagnosticEvents: diagnostics.stream,
      );
      listener.start(sourceController.stream);
      addTearDown(diagnostics.close);

      final now = DateTime.now().toUtc();
      await msgRepo.saveMessage(
        GroupMessage(
          id: 'go003-msg',
          groupId: 'group-1',
          senderPeerId: 'peer-sender',
          transportPeerId: 'peer-sender-device',
          senderUsername: 'Sender',
          text: 'Stale sender state',
          timestamp: now,
          keyGeneration: 1,
          status: 'sent',
          isIncoming: false,
          createdAt: now,
          inboxStored: true,
        ),
      );

      final emittedMessage = listener.groupMessageStream.first.timeout(
        const Duration(seconds: 1),
      );
      diagnostics.add({
        'event': 'group:publish_validation_rejected',
        'groupId': 'group-1',
        'messageId': 'go003-msg',
        'reason': 'non_member',
        'envelopeType': 'group_message',
        'keyEpoch': 1,
      });

      final updated = await emittedMessage;
      expect(updated.id, 'go003-msg');
      expect(updated.status, 'failed');
      expect(updated.isIncoming, isFalse);
      expect(updated.wireEnvelope, isNotNull);

      final stored = await msgRepo.getMessage('go003-msg');
      expect(stored, isNotNull);
      expect(stored!.status, 'failed');
      expect(stored.inboxStored, isTrue);
      expect(stored.wireEnvelope, contains('"messageId":"go003-msg"'));
      expect(stored.wireEnvelope, contains('"text":"Stale sender state"'));
    },
  );

  test(
    'SV-001 never-member message is quarantined before stream storage or notification',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      final notifService = FakeNotificationService();
      final tracker = ActiveConversationTracker();
      listener.dispose();
      listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        notificationService: notifService,
        groupConversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
      );
      final emitted = <GroupMessage>[];
      final subscription = listener.groupMessageStream.listen(emitted.add);
      addTearDown(subscription.cancel);
      addTearDown(() => debugSetFlowEventSink(null));

      listener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-never-member',
        'senderUsername': 'Never Member',
        'keyEpoch': 1,
        'text': 'SV-001 forged message',
        'timestamp': DateTime.utc(2026, 5, 14, 1).toIso8601String(),
        'messageId': 'sv001-never-member-forged',
        'transportPeerId': 'peer-never-member',
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(await msgRepo.getMessage('sv001-never-member-forged'), isNull);
      expect(await msgRepo.getLatestMessage('group-1'), isNull);
      expect(emitted, isEmpty);
      expect(notifService.shown, isEmpty);
      expect(
        flowEvents.any(
          (event) =>
              event['event'] ==
              'GROUP_MESSAGE_LISTENER_MEMBERSHIP_DEPENDENT_CONTENT_BUFFERED',
        ),
        isTrue,
      );
    },
  );

  test(
    'SV-002 removed old-key message is rejected before stream storage unread or notification',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      final notifService = FakeNotificationService();
      final tracker = ActiveConversationTracker();
      listener.dispose();
      listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        notificationService: notifService,
        groupConversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
      );
      final emitted = <GroupMessage>[];
      final subscription = listener.groupMessageStream.listen(emitted.add);
      addTearDown(subscription.cancel);
      addTearDown(() => debugSetFlowEventSink(null));

      final removedAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 10),
      );
      await msgRepo.saveMessage(
        GroupMessage(
          id:
              'sys-member_removed:group-1:peer-sender:peer-admin:'
              '${removedAt.microsecondsSinceEpoch}',
          groupId: 'group-1',
          senderPeerId: 'peer-admin',
          senderUsername: 'Admin',
          text: 'Admin removed peer-sender',
          timestamp: removedAt,
          status: 'delivered',
          isIncoming: true,
          readAt: removedAt,
          createdAt: removedAt,
        ),
      );
      await groupRepo.removeMember('group-1', 'peer-sender');
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 2,
          encryptedKey: 'sv002-current-key',
          createdAt: removedAt.add(const Duration(seconds: 1)),
        ),
      );
      final latestBefore = await msgRepo.getLatestMessage('group-1');

      listener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Removed',
        'keyEpoch': 1,
        'text': 'SV-002 removed old-key publish',
        'timestamp': removedAt
            .add(const Duration(seconds: 2))
            .toIso8601String(),
        'messageId': 'sv002-removed-old-key-listener',
        'transportPeerId': 'peer-sender',
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(
        await msgRepo.getMessage('sv002-removed-old-key-listener'),
        isNull,
      );
      expect((await msgRepo.getLatestMessage('group-1'))!.id, latestBefore!.id);
      expect(await msgRepo.getUnreadCount('group-1'), 0);
      expect(emitted, isEmpty);
      expect(notifService.shown, isEmpty);
      expect(
        flowEvents.any(
          (event) =>
              event['event'] ==
              'GROUP_HANDLE_INCOMING_MSG_REMOVED_AFTER_CUTOFF',
        ),
        isTrue,
      );
    },
  );

  test(
    'GM-014 member_added event time becomes Charlie re-add joinedAt and removed-window sender traffic stays rejected',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      final removedAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 3),
      );
      final removedWindowAt = removedAt.add(const Duration(seconds: 5));
      final readdAt = removedAt.add(const Duration(seconds: 10));
      final readdEnvelopeAt = readdAt.add(const Duration(milliseconds: 12));
      final adminMember = (await groupRepo.getMember('group-1', 'peer-admin'))!;
      final senderMember = (await groupRepo.getMember(
        'group-1',
        'peer-sender',
      ))!;
      final oldCharlie = GroupMember(
        groupId: 'group-1',
        peerId: 'peer-charlie',
        username: 'Charlie',
        role: MemberRole.writer,
        publicKey: 'pk-charlie-old',
        joinedAt: initialMemberJoinedAt,
      );
      await groupRepo.saveMember(oldCharlie);

      listener.start(sourceController.stream);
      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 1,
        'text': jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-charlie', 'username': 'Charlie'},
          'removedAt': removedAt.toIso8601String(),
          'groupConfig': buildGroupConfigPayload(testGroup, [
            adminMember,
            senderMember,
          ]),
        }),
        'timestamp': removedAt.toIso8601String(),
        'messageId': 'gm014-member-removed',
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await groupRepo.getMember('group-1', 'peer-charlie'), isNull);
      expect(
        await msgRepo.getLatestRemovalTimestampForSender(
          'group-1',
          'peer-charlie',
        ),
        removedAt,
      );

      final readdedCharlie = oldCharlie.copyWith(
        publicKey: 'pk-charlie-readd',
        joinedAt: readdAt,
      );
      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 2,
        'text': jsonEncode({
          '__sys': 'member_added',
          'eventAt': readdAt.toIso8601String(),
          'member': readdedCharlie.toConfigJson(),
          'groupConfig': buildGroupConfigPayload(testGroup, [
            adminMember,
            senderMember,
            readdedCharlie,
          ]),
        }),
        'timestamp': readdEnvelopeAt.toIso8601String(),
        'messageId': 'gm014-member-added',
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final charlieAfterReadd = await groupRepo.getMember(
        'group-1',
        'peer-charlie',
      );
      expect(charlieAfterReadd, isNotNull);
      expect(charlieAfterReadd!.joinedAt, readdAt);
      expect(charlieAfterReadd.publicKey, 'pk-charlie-readd');
      expect(
        (await groupRepo.getGroup('group-1'))!.lastMembershipEventAt,
        readdAt,
      );

      final updateConfigPayloads = bridge.sentMessages
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .where((message) => message['cmd'] == 'group:updateConfig')
          .map(
            (message) => Map<String, dynamic>.from(
              (message['payload'] as Map<String, dynamic>)['groupConfig']
                  as Map,
            ),
          )
          .toList(growable: false);
      expect(updateConfigPayloads, hasLength(2));
      final finalMemberPeerIds =
          (updateConfigPayloads.last['members'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((member) => member['peerId'] as String)
              .toList(growable: false);
      expect(finalMemberPeerIds.where((peerId) => peerId == 'peer-charlie'), [
        'peer-charlie',
      ]);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-charlie',
        'senderUsername': 'Charlie',
        'keyEpoch': 2,
        'text': 'GM-014 removed-window Charlie send',
        'timestamp': removedWindowAt.toIso8601String(),
        'messageId': 'gm014-charlie-removed-window',
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await msgRepo.getMessage('gm014-charlie-removed-window'), isNull);
      expect(
        flowEvents.any(
          (event) =>
              event['event'] ==
              'GROUP_HANDLE_INCOMING_MSG_REMOVED_WINDOW_AFTER_REJOIN',
        ),
        isTrue,
      );
    },
  );

  group('PREREQ-SIGNED-COMMIT-AUDIT', () {
    test(
      'missing audit for shipped transition families is rejected before side effects',
      () async {
        final eventLog = _FakeEventLog();
        listener.dispose();
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          appendGroupEventLogEntry: eventLog.append,
        );
        listener.start(sourceController.stream);

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'messageId': 'unsigned-member-added-1',
          'text': jsonEncode({
            '__sys': 'member_added',
            'member': {
              'peerId': 'peer-new',
              'username': 'New',
              'role': 'writer',
              'publicKey': 'pk-new',
            },
            'groupConfig': buildGroupConfigPayload(testGroup, [
              GroupMember(
                groupId: 'group-1',
                peerId: 'peer-admin',
                username: 'Admin',
                role: MemberRole.admin,
                publicKey: 'pk-admin',
                joinedAt: initialMemberJoinedAt,
              ),
              GroupMember(
                groupId: 'group-1',
                peerId: 'peer-new',
                username: 'New',
                role: MemberRole.writer,
                publicKey: 'pk-new',
                joinedAt: initialMemberJoinedAt,
              ),
            ]),
          }),
          'timestamp': '2026-05-01T12:00:00.000Z',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(await groupRepo.getMember('group-1', 'peer-new'), isNull);
        expect(msgRepo.count, 0);
        expect(eventLog.entries, isEmpty);
        expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      },
    );

    test(
      'valid signed transition applies live and duplicate replay is idempotent while tampered replay is blocked',
      () async {
        final eventLog = _FakeEventLog();
        listener.dispose();
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          appendGroupEventLogEntry: eventLog.append,
        );
        listener.start(sourceController.stream);

        final eventAt = DateTime.utc(2026, 5, 1, 12, 1);
        final member = GroupMember(
          groupId: 'group-1',
          peerId: 'peer-audit-new',
          username: 'Audited',
          role: MemberRole.writer,
          publicKey: 'pk-audit-new',
          joinedAt: eventAt,
        );
        final signedPayload = await signGroupSystemTransitionPayload(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          transitionType: 'member_added',
          sourceEventId: 'signed-member-added-1',
          eventAt: eventAt,
          actorPeerId: 'peer-admin',
          actorUsername: 'Admin',
          actorSigningPublicKey: 'pk-admin',
          actorPrivateKey: 'sk-admin',
          systemPayload: {
            '__sys': 'member_added',
            'member': member.toConfigJson(),
            'groupConfig': buildGroupConfigPayload(testGroup, [
              GroupMember(
                groupId: 'group-1',
                peerId: 'peer-admin',
                username: 'Admin',
                role: MemberRole.admin,
                publicKey: 'pk-admin',
                joinedAt: initialMemberJoinedAt,
              ),
              member,
            ]),
          },
        );
        final liveEnvelope = {
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'messageId': 'signed-member-added-1',
          'text': jsonEncode(signedPayload),
          'timestamp': eventAt.toIso8601String(),
        };

        sourceController.add(liveEnvelope);
        await Future.delayed(const Duration(milliseconds: 50));
        sourceController.add(liveEnvelope);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(
          await groupRepo.getMember('group-1', 'peer-audit-new'),
          isNotNull,
        );
        expect(eventLog.entries, hasLength(1));
        expect(msgRepo.count, 1);

        final tampered = Map<String, dynamic>.from(signedPayload)
          ..['member'] = {...member.toConfigJson(), 'username': 'Tampered'};
        sourceController.add({
          ...liveEnvelope,
          'messageId': 'signed-member-added-2',
          'text': jsonEncode(tampered),
        });
        await Future.delayed(const Duration(milliseconds: 50));

        final stored = await groupRepo.getMember('group-1', 'peer-audit-new');
        expect(stored!.username, 'Audited');
        expect(eventLog.entries, hasLength(1));
        expect(msgRepo.count, 1);
      },
    );
  });

  group('PREREQ-REMOTE-EVENT-FAMILIES', () {
    test(
      'duplicate group_message_deleted removes one exact target and keeps one tombstone',
      () async {
        final eventLog = _FakeEventLog();
        listener.dispose();
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          appendGroupEventLogEntry: eventLog.append,
        );
        listener.start(sourceController.stream);

        final messageAt = DateTime.utc(2026, 5, 1, 12);
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'delete-target-1',
            groupId: 'group-1',
            senderPeerId: 'peer-sender',
            senderUsername: 'Sender',
            text: 'Remove this',
            timestamp: messageAt,
            createdAt: messageAt,
          ),
        );
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'delete-keep-1',
            groupId: 'group-1',
            senderPeerId: 'peer-sender',
            senderUsername: 'Sender',
            text: 'Keep this',
            timestamp: messageAt,
            createdAt: messageAt,
          ),
        );

        final deletedAt = messageAt.add(const Duration(minutes: 1));
        final signedPayload = await signedAuditSystemPayload(
          transitionType: 'group_message_deleted',
          sourceEventId: 'remote-delete-event-1',
          eventAt: deletedAt,
          systemPayload: {
            '__sys': 'group_message_deleted',
            'targetMessageId': 'delete-target-1',
            'deletedAt': deletedAt.toIso8601String(),
          },
        );
        final envelope = {
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'messageId': 'remote-delete-event-1',
          'text': jsonEncode(signedPayload),
          'timestamp': deletedAt.toIso8601String(),
        };

        sourceController.add(envelope);
        sourceController.add(envelope);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(await msgRepo.getMessage('delete-target-1'), isNull);
        expect(await msgRepo.getMessage('delete-keep-1'), isNotNull);
        final messages = await msgRepo.getMessagesPage('group-1', limit: 20);
        final tombstones = messages
            .where(
              (message) =>
                  message.id.startsWith(
                    'sys-group_message_deleted:group-1:delete-target-1:',
                  ) &&
                  message.text == 'Admin deleted a message',
            )
            .toList();
        expect(tombstones, hasLength(1));
        expect(eventLog.entries, hasLength(1));
        expect(eventLog.entries.single['eventType'], 'group_message_deleted');
      },
    );

    test(
      'stale wrong-group and unauthorized group_message_deleted events do not corrupt messages',
      () async {
        listener.start(sourceController.stream);
        final messageAt = DateTime.utc(2026, 5, 1, 12);
        await groupRepo.saveGroup(
          GroupModel(
            id: 'group-2',
            name: 'Other Group',
            type: GroupType.chat,
            topicName: 'group-topic-2',
            createdAt: initialGroupCreatedAt,
            createdBy: 'peer-admin',
            myRole: GroupRole.admin,
          ),
        );
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'newer-target',
            groupId: 'group-1',
            senderPeerId: 'peer-sender',
            text: 'Newer than delete',
            timestamp: messageAt.add(const Duration(minutes: 5)),
            createdAt: messageAt,
          ),
        );
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'foreign-target',
            groupId: 'group-2',
            senderPeerId: 'peer-sender',
            text: 'Wrong group',
            timestamp: messageAt,
            createdAt: messageAt,
          ),
        );
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'admin-owned-target',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            text: 'Admin message',
            timestamp: messageAt,
            createdAt: messageAt,
          ),
        );

        void addDeleteEvent({
          required String senderId,
          required String senderUsername,
          required String messageId,
          required String targetMessageId,
          required DateTime deletedAt,
        }) {
          sourceController.add({
            'groupId': 'group-1',
            'senderId': senderId,
            'senderUsername': senderUsername,
            'keyEpoch': 0,
            'messageId': messageId,
            'text': jsonEncode({
              '__sys': 'group_message_deleted',
              'targetMessageId': targetMessageId,
              'deletedAt': deletedAt.toIso8601String(),
            }),
            'timestamp': deletedAt.toIso8601String(),
          });
        }

        addDeleteEvent(
          senderId: 'peer-admin',
          senderUsername: 'Admin',
          messageId: 'stale-delete-event',
          targetMessageId: 'newer-target',
          deletedAt: messageAt,
        );
        addDeleteEvent(
          senderId: 'peer-admin',
          senderUsername: 'Admin',
          messageId: 'wrong-group-delete-event',
          targetMessageId: 'foreign-target',
          deletedAt: messageAt.add(const Duration(minutes: 10)),
        );
        addDeleteEvent(
          senderId: 'peer-sender',
          senderUsername: 'Sender',
          messageId: 'unauthorized-delete-event',
          targetMessageId: 'admin-owned-target',
          deletedAt: messageAt.add(const Duration(minutes: 10)),
        );

        await Future.delayed(const Duration(milliseconds: 50));

        expect(await msgRepo.getMessage('newer-target'), isNotNull);
        expect(await msgRepo.getMessage('foreign-target'), isNotNull);
        expect(await msgRepo.getMessage('admin-owned-target'), isNotNull);
        final messages = await msgRepo.getMessagesPage('group-1', limit: 20);
        expect(
          messages.where(
            (message) => message.id.startsWith('sys-group_message_deleted:'),
          ),
          isEmpty,
        );
      },
    );

    test(
      'member_banned and member_unbanned are idempotent and stale ban replay is ignored',
      () async {
        final eventLog = _FakeEventLog();
        listener.dispose();
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          appendGroupEventLogEntry: eventLog.append,
        );
        listener.start(sourceController.stream);

        final joinedAt = DateTime.utc(2026, 5, 1, 11, 59);
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-target',
            username: 'Target',
            role: MemberRole.writer,
            publicKey: 'pk-target',
            joinedAt: joinedAt,
          ),
        );

        Future<void> sendSignedEvent({
          required String transitionType,
          required String sourceEventId,
          required DateTime eventAt,
          required Map<String, dynamic> systemPayload,
        }) async {
          final signedPayload = await signedAuditSystemPayload(
            transitionType: transitionType,
            sourceEventId: sourceEventId,
            eventAt: eventAt,
            systemPayload: systemPayload,
          );
          final envelope = {
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'messageId': sourceEventId,
            'text': jsonEncode(signedPayload),
            'timestamp': eventAt.toIso8601String(),
          };
          sourceController.add(envelope);
          sourceController.add(envelope);
          await Future.delayed(const Duration(milliseconds: 50));
        }

        final bannedAt = DateTime.utc(2026, 5, 1, 12);
        await sendSignedEvent(
          transitionType: 'member_banned',
          sourceEventId: 'member-banned-event-1',
          eventAt: bannedAt,
          systemPayload: {
            '__sys': 'member_banned',
            'targetPeerId': 'peer-target',
            'targetUsername': 'Target',
            'bannedAt': bannedAt.toIso8601String(),
          },
        );

        expect(await groupRepo.getMember('group-1', 'peer-target'), isNull);
        var messages = await msgRepo.getMessagesPage('group-1', limit: 20);
        expect(
          messages.where(
            (message) =>
                message.id.startsWith(
                  'sys-member_banned:group-1:peer-target:',
                ) &&
                message.text == 'Admin banned Target',
          ),
          hasLength(1),
        );
        expect(eventLog.entries, hasLength(1));

        final unbannedAt = DateTime.utc(2026, 5, 1, 12, 5);
        await sendSignedEvent(
          transitionType: 'member_unbanned',
          sourceEventId: 'member-unbanned-event-1',
          eventAt: unbannedAt,
          systemPayload: {
            '__sys': 'member_unbanned',
            'targetPeerId': 'peer-target',
            'targetUsername': 'Target',
            'unbannedAt': unbannedAt.toIso8601String(),
          },
        );

        expect(await groupRepo.getMember('group-1', 'peer-target'), isNull);
        messages = await msgRepo.getMessagesPage('group-1', limit: 20);
        expect(
          messages.where(
            (message) =>
                message.id.startsWith(
                  'sys-member_unbanned:group-1:peer-target:',
                ) &&
                message.text == 'Admin unbanned Target',
          ),
          hasLength(1),
        );
        expect(eventLog.entries, hasLength(2));

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-target',
            username: 'Target',
            role: MemberRole.writer,
            publicKey: 'pk-target',
            joinedAt: unbannedAt.add(const Duration(minutes: 1)),
          ),
        );
        final staleBanAt = DateTime.utc(2026, 5, 1, 12, 1);
        await sendSignedEvent(
          transitionType: 'member_banned',
          sourceEventId: 'member-banned-stale-after-unban',
          eventAt: staleBanAt,
          systemPayload: {
            '__sys': 'member_banned',
            'targetPeerId': 'peer-target',
            'targetUsername': 'Target',
            'bannedAt': staleBanAt.toIso8601String(),
          },
        );

        final targetAfterStaleBan = await groupRepo.getMember(
          'group-1',
          'peer-target',
        );
        expect(targetAfterStaleBan, isNotNull);
        expect(targetAfterStaleBan!.joinedAt.isAfter(staleBanAt), isTrue);
        messages = await msgRepo.getMessagesPage('group-1', limit: 20);
        expect(
          messages.where(
            (message) =>
                message.id.startsWith('sys-member_banned:group-1:peer-target:'),
          ),
          hasLength(1),
        );
        expect(eventLog.entries, hasLength(2));
      },
    );
  });

  test('processes valid message', () async {
    listener.start(sourceController.stream);

    sourceController.add({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'text': 'Hello group!',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    // Allow async processing
    await Future.delayed(const Duration(milliseconds: 50));

    expect(msgRepo.count, 1);
    final latest = await msgRepo.getLatestMessage('group-1');
    expect(latest!.text, 'Hello group!');
  });

  test('drops events with neither text nor media — empty bubble after cold '
      'restart regression', () async {
    // Regression for the user-reported bug: after the app was killed
    // and reopened, opening an old group thread showed empty bubbles.
    // Root cause walked in this branch: group_message_listener._handleMessage
    // used `data['text'] as String? ?? ''` and saved the row even when
    // `text` was missing/null with no media. After a cold restart the
    // empty-text row was reloaded and rendered as a blank bubble.
    // The fix bails early on text-less + media-less events; this test
    // is the regression guard.
    final flowEvents = <Map<String, dynamic>>[];
    debugSetFlowEventSink(flowEvents.add);
    addTearDown(() => debugSetFlowEventSink(null));

    final emitted = <GroupMessage>[];
    final subscription = listener.groupMessageStream.listen(emitted.add);
    addTearDown(subscription.cancel);

    listener.start(sourceController.stream);

    // Event from upstream that mimics a malformed/partial-decrypt payload:
    // valid groupId + senderId, but no `text` field at all and no media.
    sourceController.add({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'messageId': 'msg-empty-drop-1',
    });

    await Future.delayed(const Duration(milliseconds: 50));

    // No row persisted — this is the load-bearing assertion. Without
    // the fix the row would be saved with text='' and survive cold
    // restarts as an empty bubble.
    expect(
      msgRepo.count,
      0,
      reason:
          'event with neither text nor media must not be persisted '
          '(would render as empty bubble after cold restart)',
    );
    expect(await msgRepo.getMessage('msg-empty-drop-1'), isNull);
    expect(await msgRepo.getLatestMessage('group-1'), isNull);

    // No live UI emission either — the conversation screen would
    // otherwise upsert an empty-text bubble in memory until restart.
    expect(emitted, isEmpty);

    // Diagnostic event must fire so the failure is visible in FLOW
    // logs from real devices.
    final dropEvents = flowEvents
        .where((e) => e['event'] == 'GROUP_MESSAGE_LISTENER_EMPTY_DROP')
        .toList();
    expect(
      dropEvents,
      hasLength(1),
      reason:
          'GROUP_MESSAGE_LISTENER_EMPTY_DROP must be emitted once so '
          'production logs reveal which upstream events are malformed',
    );
    final details = dropEvents.single['details'] as Map<String, dynamic>;
    expect(details['hasTextField'], false);
  });

  test('drops events where text is present but null, with no media', () async {
    // Sister case: Go bridge sends `text: null` instead of omitting
    // the key. The String? coercion at the listener entry treats null
    // and missing identically; the guard must catch both.
    final flowEvents = <Map<String, dynamic>>[];
    debugSetFlowEventSink(flowEvents.add);
    addTearDown(() => debugSetFlowEventSink(null));

    listener.start(sourceController.stream);

    sourceController.add({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'text': null,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'messageId': 'msg-empty-drop-null',
    });

    await Future.delayed(const Duration(milliseconds: 50));

    expect(msgRepo.count, 0);
    expect(
      flowEvents.where(
        (e) => e['event'] == 'GROUP_MESSAGE_LISTENER_EMPTY_DROP',
      ),
      hasLength(1),
    );
  });

  test(
    'allows media-only messages with empty text — legitimate sender shape',
    () async {
      // The send-side use case (send_group_message_use_case.dart:483)
      // permits messages with empty text as long as media is present.
      // The empty-drop guard must NOT regress that path: we only care
      // here that the drop event is NOT emitted, which is the precise
      // contract this guard owes. Whether the row ultimately persists
      // depends on the rest of the pipeline (sender membership, dedupe,
      // media validation) — that is covered by other tests in this file.
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      listener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': '',
        'media': [
          {
            'url': 'mknoon://blob/abc',
            'kind': 'image',
            'contentHash': _validContentHash,
            'mimeType': 'image/jpeg',
            'size': 123,
          },
        ],
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'messageId': 'msg-media-only-1',
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(
        flowEvents.where(
          (e) => e['event'] == 'GROUP_MESSAGE_LISTENER_EMPTY_DROP',
        ),
        isEmpty,
      );
    },
  );

  test(
    'ER002 rejects unknown sender message before stream, storage, or notification',
    () async {
      final notifService = FakeNotificationService();
      final tracker = ActiveConversationTracker();
      listener.dispose();
      listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        notificationService: notifService,
        groupConversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
      );
      final emitted = <GroupMessage>[];
      final subscription = listener.groupMessageStream.listen(emitted.add);
      addTearDown(subscription.cancel);

      listener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-unknown',
        'senderUsername': 'Unknown',
        'keyEpoch': 0,
        'text': 'Ghost message',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'messageId': 'msg-er002-unknown',
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(await msgRepo.getMessage('msg-er002-unknown'), isNull);
      expect(await msgRepo.getLatestMessage('group-1'), isNull);
      expect(emitted, isEmpty);
      expect(notifService.shown, isEmpty);
    },
  );

  test('forwards quotedMessageId from event into persisted message', () async {
    listener.start(sourceController.stream);

    sourceController.add({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'text': 'Quoted group reply',
      'quotedMessageId': 'msg-parent-1',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    await Future.delayed(const Duration(milliseconds: 50));

    final latest = await msgRepo.getLatestMessage('group-1');
    expect(latest, isNotNull);
    expect(latest!.quotedMessageId, 'msg-parent-1');
  });

  test('caches self peer id across multiple handled messages', () async {
    var selfPeerIdCalls = 0;
    listener = GroupMessageListener(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      bridge: bridge,
      getSelfPeerId: () async {
        selfPeerIdCalls++;
        return 'peer-self';
      },
    );

    listener.start(sourceController.stream);

    sourceController.add({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'text': 'First message',
      'messageId': 'msg-self-cache-1',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
    sourceController.add({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'text': 'Second message',
      'messageId': 'msg-self-cache-2',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    await Future.delayed(const Duration(milliseconds: 50));

    expect(msgRepo.count, 2);
    expect(selfPeerIdCalls, 1);
  });

  test(
    'DE-017 content before member add is buffered then respects joined interval',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      listener.start(sourceController.stream);

      final deliveredFuture = listener.groupMessageStream
          .where((message) => message.id == 'de017-post-add-content')
          .first
          .timeout(const Duration(seconds: 1));

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-late',
        'senderUsername': 'Late',
        'keyEpoch': 1,
        'messageId': 'de017-pre-join-content',
        'text': 'DE-017 should stay before join',
        'timestamp': '2026-04-05T12:00:00.000Z',
      });
      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-late',
        'senderUsername': 'Late',
        'keyEpoch': 1,
        'messageId': 'de017-post-add-content',
        'text': 'DE-017 should deliver after join',
        'timestamp': '2026-04-05T12:00:02.000Z',
      });

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await msgRepo.getMessage('de017-pre-join-content'), isNull);
      expect(await msgRepo.getMessage('de017-post-add-content'), isNull);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'messageId': 'de017-member-added',
        'text': jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': 'peer-late',
            'username': 'Late',
            'role': 'writer',
            'publicKey': 'pk-late',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
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
              {
                'peerId': 'peer-late',
                'username': 'Late',
                'role': 'writer',
                'publicKey': 'pk-late',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': initialGroupCreatedAt.toIso8601String(),
          },
        }),
        'timestamp': '2026-04-05T12:00:01.000Z',
      });

      final delivered = await deliveredFuture;
      expect(delivered.text, 'DE-017 should deliver after join');
      expect(await groupRepo.getMember('group-1', 'peer-late'), isNotNull);
      expect(await msgRepo.getMessage('de017-pre-join-content'), isNull);
      expect(await msgRepo.getMessage('de017-post-add-content'), isNotNull);

      final eventNames = flowEvents
          .map((event) => event['event'] as String)
          .toList(growable: false);
      expect(
        eventNames,
        containsAll([
          'GROUP_MESSAGE_LISTENER_MEMBERSHIP_DEPENDENT_CONTENT_BUFFERED',
          'GROUP_MESSAGE_LISTENER_MEMBERSHIP_DEPENDENT_CONTENT_FLUSHED',
          'GROUP_HANDLE_INCOMING_MSG_SENDER_BEFORE_JOINED_REJECTED',
        ]),
      );
    },
  );

  test(
    'DE-017 member removal repairs post-removal content while preserving prior content',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      listener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'messageId': 'de017-before-removal-content',
        'text': 'DE-017 pre-removal content remains',
        'timestamp': '2026-04-05T12:00:00.000Z',
      });
      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'messageId': 'de017-after-removal-content',
        'text': 'DE-017 post-removal content is repaired out',
        'timestamp': '2026-04-05T12:00:02.000Z',
      });

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        await msgRepo.getMessage('de017-before-removal-content'),
        isNotNull,
      );
      expect(
        await msgRepo.getMessage('de017-after-removal-content'),
        isNotNull,
      );

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'messageId': 'de017-member-removed',
        'text': jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-sender', 'username': 'Sender'},
          'removedAt': '2026-04-05T12:00:01.000Z',
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'username': 'Admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': initialGroupCreatedAt.toIso8601String(),
          },
        }),
        'timestamp': '2026-04-05T12:00:01.000Z',
      });

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await groupRepo.getMember('group-1', 'peer-sender'), isNull);
      expect(
        await msgRepo.getMessage('de017-before-removal-content'),
        isNotNull,
      );
      expect(await msgRepo.getMessage('de017-after-removal-content'), isNull);
      expect(
        flowEvents.map((event) => event['event']),
        contains(
          'GROUP_MESSAGE_LISTENER_MEMBERSHIP_DEPENDENT_CONTENT_REPAIRED',
        ),
      );
    },
  );

  test(
    'DE-012 dispatcher overflow triggers one replay recovery and coalesces duplicates',
    () async {
      final diagnostics = StreamController<Map<String, dynamic>>.broadcast();
      final recoveryStarted = Completer<void>();
      final recoveryGate = Completer<void>();
      final recoveries = <Map<String, dynamic>>[];
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));
      addTearDown(diagnostics.close);

      listener.dispose();
      listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        groupDiagnosticEvents: diagnostics.stream,
        recoverFromDispatcherOverflow: (diagnostic) async {
          recoveries.add(diagnostic);
          if (!recoveryStarted.isCompleted) {
            recoveryStarted.complete();
          }
          await recoveryGate.future;
        },
      );
      listener.start(sourceController.stream);

      diagnostics.add({
        'event': 'group:dispatcher_overflow',
        'state': 'overflow',
        'lastEvent': 'group_message:received',
        'droppedCount': 1,
        'queueDepth': 2,
        'maxQueueSize': 2,
      });

      await recoveryStarted.future.timeout(const Duration(seconds: 1));
      expect(recoveries, hasLength(1));
      expect(recoveries.single['lastEvent'], 'group_message:received');

      diagnostics.add({
        'event': 'group:dispatcher_overflow',
        'state': 'overflow',
        'lastEvent': 'group_message:received',
        'droppedCount': 2,
        'queueDepth': 2,
        'maxQueueSize': 2,
      });
      diagnostics.add({
        'event': 'group:dispatcher_overflow',
        'state': 'overflow',
        'lastEvent': 'group_reaction:received',
        'droppedCount': 1,
        'queueDepth': 2,
        'maxQueueSize': 2,
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(recoveries, hasLength(1));
      expect(msgRepo.count, 0);

      recoveryGate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final eventNames = flowEvents
          .map((event) => event['event'] as String)
          .toList(growable: false);
      expect(
        eventNames,
        containsAll([
          'GROUP_DISPATCHER_OVERFLOW_RECOVERY_REQUESTED',
          'GROUP_DISPATCHER_OVERFLOW_RECOVERY_COALESCED',
          'GROUP_DISPATCHER_OVERFLOW_RECOVERY_IGNORED',
          'GROUP_DISPATCHER_OVERFLOW_RECOVERY_DONE',
        ]),
      );
    },
  );

  test(
    'IR-017 dispatcher overflow diagnostic names replay recovery reason',
    () async {
      final diagnostics = StreamController<Map<String, dynamic>>.broadcast();
      final recoveryDone = Completer<void>();
      final recoveries = <Map<String, dynamic>>[];
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));
      addTearDown(diagnostics.close);

      listener.dispose();
      listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        groupDiagnosticEvents: diagnostics.stream,
        recoverFromDispatcherOverflow: (diagnostic) async {
          recoveries.add(diagnostic);
          if (!recoveryDone.isCompleted) {
            recoveryDone.complete();
          }
        },
      );
      listener.start(sourceController.stream);

      diagnostics.add({
        'event': 'group:dispatcher_overflow',
        'state': 'overflow',
        'lastEvent': 'group_message:received',
        'droppedCount': 3,
        'queueDepth': 4,
        'maxQueueSize': 4,
      });

      await recoveryDone.future.timeout(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(recoveries, hasLength(1));
      expect(recoveries.single['lastEvent'], 'group_message:received');
      expect(recoveries.single['droppedCount'], 3);
      expect(msgRepo.count, 0);

      final requested = flowEvents.singleWhere(
        (event) =>
            event['event'] == 'GROUP_DISPATCHER_OVERFLOW_RECOVERY_REQUESTED',
      );
      final done = flowEvents.singleWhere(
        (event) => event['event'] == 'GROUP_DISPATCHER_OVERFLOW_RECOVERY_DONE',
      );
      final requestedDetails = requested['details'] as Map<String, dynamic>;
      final doneDetails = done['details'] as Map<String, dynamic>;
      for (final details in [requestedDetails, doneDetails]) {
        expect(details['state'], 'overflow');
        expect(details['lastEvent'], 'group_message:received');
        expect(details['droppedCount'], 3);
        expect(details['queueDepth'], 4);
        expect(details['maxQueueSize'], 4);
      }
    },
  );

  test(
    'DE-013 malformed group message schema rejects before persistence and valid later event persists',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      listener.start(sourceController.stream);
      final emitted = listener.groupMessageStream.first.timeout(
        const Duration(seconds: 1),
      );
      final now = DateTime.now().toUtc().toIso8601String();

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'text': 'missing epoch',
        'timestamp': now,
        'messageId': 'de013-missing-key-epoch',
      });
      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 42,
        'timestamp': now,
        'messageId': 'de013-invalid-text',
      });
      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'invalid media entry',
        'media': [42],
        'timestamp': now,
        'messageId': 'de013-invalid-media-entry',
      });

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await msgRepo.getMessage('de013-missing-key-epoch'), isNull);
      expect(await msgRepo.getMessage('de013-invalid-text'), isNull);
      expect(await msgRepo.getMessage('de013-invalid-media-entry'), isNull);
      expect(msgRepo.count, 0);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'valid after malformed schema',
        'timestamp': now,
        'messageId': 'de013-valid-after-malformed',
      });

      final valid = await emitted;
      expect(valid.id, 'de013-valid-after-malformed');
      expect(valid.text, 'valid after malformed schema');
      expect(
        await msgRepo.getMessage('de013-valid-after-malformed'),
        isNotNull,
      );

      final schemaRejectReasons = flowEvents
          .where(
            (event) =>
                event['event'] == 'GROUP_MESSAGE_LISTENER_SCHEMA_REJECTED',
          )
          .map((event) {
            final details = event['details'] as Map<String, dynamic>;
            return details['reason'] as String;
          })
          .toList(growable: false);
      expect(
        schemaRejectReasons,
        containsAll([
          'missing_or_invalid_keyEpoch',
          'invalid_text',
          'invalid_media_entry',
        ]),
      );
    },
  );

  test('ignores message for unknown group', () async {
    listener.start(sourceController.stream);

    sourceController.add({
      'groupId': 'unknown-group',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'text': 'Hello',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    await Future.delayed(const Duration(milliseconds: 50));

    expect(msgRepo.count, 0);
  });

  test('emits to stream on valid message', () async {
    listener.start(sourceController.stream);

    final messages = <GroupMessage>[];
    final subscription = listener.groupMessageStream.listen(messages.add);

    sourceController.add({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'text': 'Streamed message',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    await Future.delayed(const Duration(milliseconds: 50));

    expect(messages.length, 1);
    expect(messages.first.text, 'Streamed message');

    await subscription.cancel();
  });

  test('disposes correctly', () async {
    listener.start(sourceController.stream);
    listener.dispose();

    // After disposal, adding data should not cause errors
    sourceController.add({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'text': 'After dispose',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    await Future.delayed(const Duration(milliseconds: 50));

    // Message was not processed because subscription was cancelled
    expect(msgRepo.count, 0);
  });

  test('handles malformed data without crashing', () async {
    listener.start(sourceController.stream);

    // Missing required fields
    sourceController.add({'groupId': '', 'senderId': ''});

    await Future.delayed(const Duration(milliseconds: 50));

    // Should not crash; message ignored
    expect(msgRepo.count, 0);
  });

  test(
    'KE-017 higher epoch group_message requests repair and persists once',
    () async {
      const expectedReason = 'received_message_epoch_missing_local_key';
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'local-epoch-1',
          createdAt: DateTime.utc(2026, 5, 11),
        ),
      );
      final repairRequests = <GroupKeyRepairRequest>[];
      listener.dispose();
      listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        requestGroupKeyRepair: repairRequests.add,
      );
      listener.start(sourceController.stream);

      final emittedMessage = listener.groupMessageStream.first.timeout(
        const Duration(seconds: 1),
      );
      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 2,
        'messageId': 'ke017h1',
        'text': 'KE-017 higher epoch live delivery',
        'timestamp': DateTime.utc(2026, 5, 11, 12).toIso8601String(),
      });

      final emitted = await emittedMessage;
      await Future<void>.delayed(Duration.zero);

      expect(emitted.id, 'ke017h1');
      expect(emitted.status, 'delivered');
      expect(emitted.isIncoming, isTrue);
      expect(emitted.keyGeneration, 2);
      final persisted = await msgRepo.getMessage('ke017h1');
      expect(persisted, isNotNull);
      expect(persisted!.text, 'KE-017 higher epoch live delivery');
      expect(msgRepo.count, 1);

      expect(repairRequests, hasLength(1));
      expect(repairRequests.single.groupId, 'group-1');
      expect(repairRequests.single.keyEpoch, 2);
      expect(repairRequests.single.reason, expectedReason);
      expect(repairRequests.single.messageId, 'ke017h1');

      final diagnostics = flowEvents
          .where(
            (event) =>
                event['event'] ==
                'GROUP_RECEIVED_MESSAGE_KEY_EPOCH_AHEAD_OF_LOCAL',
          )
          .toList();
      expect(diagnostics, hasLength(1));
      final details = diagnostics.single['details'] as Map<String, dynamic>;
      expect(details['groupId'], 'group-1');
      expect(details['messageId'], 'ke017h1');
      expect(details['incomingKeyEpoch'], 2);
      expect(details['localKeyEpoch'], 1);
      expect(details['reason'], expectedReason);
      expect(details.containsKey('encryptedKey'), isFalse);
    },
  );

  test('KE-017 matching local epoch does not request repair', () async {
    final flowEvents = <Map<String, dynamic>>[];
    debugSetFlowEventSink(flowEvents.add);
    addTearDown(() => debugSetFlowEventSink(null));
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 2,
        encryptedKey: 'local-epoch-2',
        createdAt: DateTime.utc(2026, 5, 11),
      ),
    );
    final repairRequests = <GroupKeyRepairRequest>[];
    listener.dispose();
    listener = GroupMessageListener(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      bridge: bridge,
      requestGroupKeyRepair: repairRequests.add,
    );
    listener.start(sourceController.stream);

    final emittedMessage = listener.groupMessageStream.first.timeout(
      const Duration(seconds: 1),
    );
    sourceController.add({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 2,
      'messageId': 'ke017same',
      'text': 'KE-017 same epoch live delivery',
      'timestamp': DateTime.utc(2026, 5, 11, 12, 1).toIso8601String(),
    });

    final emitted = await emittedMessage;
    await Future<void>.delayed(Duration.zero);

    expect(emitted.id, 'ke017same');
    expect(emitted.keyGeneration, 2);
    expect(await msgRepo.getMessage('ke017same'), isNotNull);
    expect(msgRepo.count, 1);
    expect(repairRequests, isEmpty);
    expect(
      flowEvents.where(
        (event) =>
            event['event'] == 'GROUP_RECEIVED_MESSAGE_KEY_EPOCH_AHEAD_OF_LOCAL',
      ),
      isEmpty,
    );
  });

  group('system messages', () {
    test('member_added saves member and calls updateConfig', () async {
      listener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'member_added',
        'member': {
          'peerId': 'peer-charlie',
          'username': 'Charlie',
          'role': 'writer',
          'publicKey': 'pk-charlie',
        },
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-admin', 'role': 'admin', 'publicKey': 'pk-admin'},
            {
              'peerId': 'peer-sender',
              'role': 'writer',
              'publicKey': 'pk-sender',
            },
            {
              'peerId': 'peer-charlie',
              'role': 'writer',
              'publicKey': 'pk-charlie',
            },
          ],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      // System message should materialize one durable timeline row, not a raw
      // duplicate chat payload.
      expect(msgRepo.count, 1);
      final latest = await msgRepo.getLatestMessage('group-1');
      expect(latest, isNotNull);
      expect(latest!.text, 'Admin added Charlie');

      // New member should be saved to the group repo
      final charlie = await groupRepo.getMember('group-1', 'peer-charlie');
      expect(charlie, isNotNull);
      expect(charlie!.username, 'Charlie');
      expect(charlie.role, MemberRole.writer);

      // Bridge should have received group:updateConfig
      expect(bridge.commandLog, contains('group:updateConfig'));
    });

    test('unauthorized member_added is ignored', () async {
      listener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'member_added',
        'member': {
          'peerId': 'peer-charlie',
          'username': 'Charlie',
          'role': 'writer',
          'publicKey': 'pk-charlie',
        },
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-admin', 'role': 'admin', 'publicKey': 'pk-admin'},
            {
              'peerId': 'peer-sender',
              'role': 'writer',
              'publicKey': 'pk-sender',
            },
            {
              'peerId': 'peer-charlie',
              'role': 'writer',
              'publicKey': 'pk-charlie',
            },
          ],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(await groupRepo.getMember('group-1', 'peer-charlie'), isNull);
      expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      expect(msgRepo.count, 0);
    });

    test(
      'authorized admin metadata event with valid state hash but no signed actor envelope is ignored',
      () async {
        await saveTrustedAdminMember();
        final eventLog = _FakeEventLog();
        listener.dispose();
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          appendGroupEventLogEntry: eventLog.append,
        );
        listener.start(sourceController.stream);

        final updatedAt = DateTime.parse('2026-04-05T12:19:00.000Z');
        final sysText = jsonEncode({
          '__sys': 'group_metadata_updated',
          'updatedAt': updatedAt.toUtc().toIso8601String(),
          'groupConfig': buildMetadataConfig(updatedAt: updatedAt),
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'messageId': 'metadata-unsigned-1',
          'text': sysText,
          'timestamp': updatedAt.toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final group = await groupRepo.getGroup('group-1');
        expect(group, isNotNull);
        expect(group!.name, 'Test Group');
        expect(group.description, isNull);
        expect(group.lastMetadataEventAt, isNull);
        expect(bridge.commandLog, isNot(contains('payload.verify')));
        expect(bridge.commandLog, isNot(contains('group:updateConfig')));
        expect(msgRepo.count, 0);
        expect(eventLog.entries, isEmpty);
      },
    );

    test(
      'group_metadata_updated refreshes group metadata and stores a timeline event',
      () async {
        await saveTrustedAdminMember();
        bridge.responses['payload.verify'] = {'ok': true, 'valid': true};
        final eventLog = _FakeEventLog();
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          appendGroupEventLogEntry: eventLog.append,
          downloadGroupAvatarFn:
              ({
                required dynamic bridge,
                required String groupId,
                required String blobId,
              }) async => 'media/group_avatars/$groupId.jpg',
        );
        listener.start(sourceController.stream);

        final updatedAt = DateTime.parse('2026-04-05T12:20:00.000Z');
        final groupConfig = buildMetadataConfig(
          updatedAt: updatedAt,
          avatarBlobId: 'blob-1',
          avatarMime: 'image/jpeg',
        );
        final metadataPayload = signedMetadataSystemPayload(
          updatedAt: updatedAt,
          groupConfig: groupConfig,
        );
        final sysPayload = await signedAuditSystemPayload(
          transitionType: 'group_metadata_updated',
          sourceEventId: 'metadata-valid-1',
          eventAt: updatedAt,
          systemPayload: metadataPayload,
        );
        final sysText = jsonEncode(sysPayload);

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'messageId': 'metadata-valid-1',
          'text': sysText,
          'timestamp': updatedAt.toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final updatedGroup = await groupRepo.getGroup('group-1');
        expect(updatedGroup, isNotNull);
        expect(updatedGroup!.name, 'Renamed Group');
        expect(updatedGroup.description, 'Fresh description');
        expect(updatedGroup.avatarBlobId, 'blob-1');
        expect(updatedGroup.avatarMime, 'image/jpeg');
        expect(updatedGroup.avatarPath, 'media/group_avatars/group-1.jpg');
        expect(updatedGroup.lastMetadataEventAt, updatedAt.toUtc());

        final latest = await msgRepo.getLatestMessage('group-1');
        expect(latest, isNotNull);
        expect(latest!.text, 'Admin updated the group details');
        final verifyIndex = bridge.commandLog.indexOf('payload.verify');
        final updateConfigIndex = bridge.commandLog.indexOf(
          'group:updateConfig',
        );
        expect(verifyIndex, isNonNegative);
        expect(updateConfigIndex, isNonNegative);
        expect(verifyIndex, lessThan(updateConfigIndex));

        final actorEvent = sysPayload['actorEvent'] as Map<String, dynamic>;
        final verifyMsg = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          final payload = parsed['payload'] as Map<String, dynamic>?;
          return parsed['cmd'] == 'payload.verify' &&
              payload?['data'] == actorEvent['signedPayload'];
        });
        final verifyPayload =
            (jsonDecode(verifyMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        expect(verifyPayload['publicKey'], 'pk-admin');
        expect(verifyPayload['data'], actorEvent['signedPayload']);
        expect(verifyPayload['signature'], actorEvent['signature']);
        expect(eventLog.entries, hasLength(1));
      },
    );

    test(
      'KE-010 key-before-config rejects regular message until local recipient membership arrives',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        addTearDown(() => debugSetFlowEventSink(null));
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 2,
            encryptedKey: 'ke010-current-key-before-config',
            createdAt: DateTime.utc(2026, 5, 12, 11, 45),
          ),
        );
        final repairRequests = <GroupKeyRepairRequest>[];
        listener.dispose();
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-charlie',
          requestGroupKeyRepair: repairRequests.add,
        );
        listener.start(sourceController.stream);

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 2,
          'messageId': 'ke010-pre-config',
          'text': 'KE-010 pre-config plaintext must not persist',
          'timestamp': DateTime.utc(2026, 5, 12, 11, 46).toIso8601String(),
        });
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(await msgRepo.getMessage('ke010-pre-config'), isNull);
        expect(msgRepo.count, 0);
        expect(repairRequests, isEmpty);
        expect(
          flowEvents.any(
            (event) =>
                event['event'] ==
                'GROUP_HANDLE_INCOMING_MSG_LOCAL_MEMBERSHIP_MISSING',
          ),
          isTrue,
        );

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-charlie',
            joinedAt: DateTime.utc(2026, 5, 12, 11, 47),
          ),
        );

        final emittedMessage = listener.groupMessageStream.first.timeout(
          const Duration(seconds: 1),
        );
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 2,
          'messageId': 'ke010-post-config',
          'text': 'KE-010 post-config plaintext may persist',
          'timestamp': DateTime.utc(2026, 5, 12, 11, 48).toIso8601String(),
        });

        final emitted = await emittedMessage;
        expect(emitted.id, 'ke010-post-config');
        expect(emitted.keyGeneration, 2);
        expect(await msgRepo.getMessage('ke010-post-config'), isNotNull);
        expect(msgRepo.count, 1);
        expect(repairRequests, isEmpty);
      },
    );

    test(
      'DB002 logs membership and metadata events and blocks changed replay before mutation',
      () async {
        bridge.responses['payload.verify'] = {'ok': true, 'valid': true};
        final eventLog = _FakeEventLog();
        listener.dispose();
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          appendGroupEventLogEntry: eventLog.append,
        );
        listener.start(sourceController.stream);

        const memberEventAt = '2026-04-05T12:24:00.000Z';
        Map<String, dynamic> memberAddedPayload(String peerId) => {
          '__sys': 'member_added',
          'member': {
            'peerId': peerId,
            'username': peerId == 'peer-charlie' ? 'Charlie' : 'Eve',
            'role': 'writer',
            'publicKey': 'pk-$peerId',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
              {'peerId': peerId, 'role': 'writer', 'publicKey': 'pk-$peerId'},
            ],
            'createdBy': 'peer-admin',
            'createdAt': initialGroupCreatedAt.toIso8601String(),
          },
        };

        final signedMemberPayload = await signedAuditSystemPayload(
          transitionType: 'member_added',
          sourceEventId: 'db002-member-added-1',
          eventAt: DateTime.parse(memberEventAt),
          systemPayload: memberAddedPayload('peer-charlie'),
        );

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'messageId': 'db002-member-added-1',
          'text': jsonEncode(signedMemberPayload),
          'timestamp': memberEventAt,
        });
        await Future.delayed(const Duration(milliseconds: 50));

        expect(await groupRepo.getMember('group-1', 'peer-charlie'), isNotNull);
        expect(eventLog.entries, hasLength(1));
        expect(eventLog.entries.single['eventType'], 'member_added');

        final tamperedMemberPayload = {
          ...memberAddedPayload('peer-eve'),
          signedGroupTransitionAuditField:
              signedMemberPayload[signedGroupTransitionAuditField],
        };
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'messageId': 'db002-member-added-1',
          'text': jsonEncode(tamperedMemberPayload),
          'timestamp': memberEventAt,
        });
        await Future.delayed(const Duration(milliseconds: 50));

        expect(eventLog.entries, hasLength(1));
        expect(await groupRepo.getMember('group-1', 'peer-eve'), isNull);
        expect(msgRepo.count, 1);

        final metadataAt = DateTime.parse('2026-04-05T12:25:00.000Z');
        Map<String, dynamic> metadataPayload(String name) {
          final groupConfig = buildMetadataConfig(
            updatedAt: metadataAt,
            name: name,
          );
          return signedMetadataSystemPayload(
            updatedAt: metadataAt,
            groupConfig: groupConfig,
          );
        }

        final signedMetadataPayload = await signedAuditSystemPayload(
          transitionType: 'group_metadata_updated',
          sourceEventId: 'db002-metadata-1',
          eventAt: metadataAt,
          systemPayload: metadataPayload('DB002 Verified Name'),
        );

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'messageId': 'db002-metadata-1',
          'text': jsonEncode(signedMetadataPayload),
          'timestamp': metadataAt.toUtc().toIso8601String(),
        });
        await Future.delayed(const Duration(milliseconds: 50));

        final updatedGroup = await groupRepo.getGroup('group-1');
        expect(updatedGroup, isNotNull);
        expect(updatedGroup!.name, 'DB002 Verified Name');
        expect(eventLog.entries, hasLength(2));
        expect(eventLog.entries.last['eventType'], 'group_metadata_updated');

        final tamperedMetadataPayload = {
          ...metadataPayload('DB002 Tampered Name'),
          signedGroupTransitionAuditField:
              signedMetadataPayload[signedGroupTransitionAuditField],
        };
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'messageId': 'db002-metadata-1',
          'text': jsonEncode(tamperedMetadataPayload),
          'timestamp': metadataAt.toUtc().toIso8601String(),
        });
        await Future.delayed(const Duration(milliseconds: 50));

        expect(eventLog.entries, hasLength(2));
        expect(
          (await groupRepo.getGroup('group-1'))!.name,
          'DB002 Verified Name',
        );
        expect(msgRepo.count, 2);
      },
    );

    test('signed group_metadata_updated payload mismatch is ignored', () async {
      await saveTrustedAdminMember();
      bridge.responses['payload.verify'] = {'ok': true, 'valid': true};
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start(sourceController.stream);

      final updatedAt = DateTime.parse('2026-04-05T12:21:00.000Z');
      final outerConfig = buildMetadataConfig(
        updatedAt: updatedAt,
        name: 'Outer Name',
      );
      final signedConfig = buildMetadataConfig(
        updatedAt: updatedAt,
        name: 'Signed Name',
      );
      final sysText = jsonEncode(
        signedMetadataSystemPayload(
          updatedAt: updatedAt,
          groupConfig: outerConfig,
          signedGroupConfig: signedConfig,
        ),
      );

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'messageId': 'metadata-mismatch-1',
        'text': sysText,
        'timestamp': updatedAt.toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      final group = await groupRepo.getGroup('group-1');
      expect(group, isNotNull);
      expect(group!.name, 'Test Group');
      expect(group.description, isNull);
      expect(group.lastMetadataEventAt, isNull);
      expect(bridge.commandLog, isNot(contains('payload.verify')));
      expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      expect(msgRepo.count, 0);
      expect(eventLog.entries, isEmpty);
    });

    test('invalid group_metadata_updated actor signature is ignored', () async {
      await saveTrustedAdminMember();
      bridge.responses['payload.verify'] = {'ok': true, 'valid': false};
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start(sourceController.stream);

      final updatedAt = DateTime.parse('2026-04-05T12:23:00.000Z');
      final sysPayload = await signedAuditSystemPayload(
        transitionType: 'group_metadata_updated',
        sourceEventId: 'metadata-invalid-signature-1',
        eventAt: updatedAt,
        systemPayload: signedMetadataSystemPayload(
          updatedAt: updatedAt,
          groupConfig: buildMetadataConfig(updatedAt: updatedAt),
        ),
      );
      final sysText = jsonEncode(sysPayload);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'messageId': 'metadata-invalid-signature-1',
        'text': sysText,
        'timestamp': updatedAt.toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      final group = await groupRepo.getGroup('group-1');
      expect(group, isNotNull);
      expect(group!.name, 'Test Group');
      expect(group.description, isNull);
      expect(group.lastMetadataEventAt, isNull);
      expect(bridge.commandLog, contains('payload.verify'));
      expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      expect(msgRepo.count, 0);
      expect(eventLog.entries, isEmpty);
    });

    test(
      'tampered group_metadata_updated state hash is ignored without mutating group state',
      () async {
        listener.start(sourceController.stream);

        final updatedAt = DateTime.parse('2026-04-05T12:22:00.000Z');
        final config = buildGroupConfigPayload(
          testGroup.copyWith(
            name: 'Renamed Group',
            description: 'Fresh description',
            lastMetadataEventAt: updatedAt,
          ),
          [
            GroupMember(
              groupId: 'group-1',
              peerId: 'peer-admin',
              username: 'Admin',
              role: MemberRole.admin,
              publicKey: 'pk-admin',
              joinedAt: initialGroupCreatedAt,
            ),
            GroupMember(
              groupId: 'group-1',
              peerId: 'peer-sender',
              username: 'Sender',
              role: MemberRole.writer,
              publicKey: 'pk-sender',
              joinedAt: initialMemberJoinedAt,
            ),
          ],
        );
        final tamperedConfig = Map<String, dynamic>.from(config)
          ..['name'] = 'Tampered Group';
        final sysText = jsonEncode({
          '__sys': 'group_metadata_updated',
          'updatedAt': updatedAt.toUtc().toIso8601String(),
          'groupConfig': tamperedConfig,
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': updatedAt.toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final group = await groupRepo.getGroup('group-1');
        expect(group, isNotNull);
        expect(group!.name, 'Test Group');
        expect(group.description, isNull);
        expect(group.lastMetadataEventAt, isNull);
        expect(bridge.commandLog, isNot(contains('group:updateConfig')));
        expect(msgRepo.count, 0);
      },
    );

    test('unauthorized group_metadata_updated is ignored', () async {
      listener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'group_metadata_updated',
        'updatedAt': '2026-04-05T12:21:00.000Z',
        'groupConfig': {
          'name': 'Hijacked Name',
          'groupType': 'chat',
          'description': 'Malicious',
          'members': [
            {'peerId': 'peer-admin', 'role': 'admin', 'publicKey': 'pk-admin'},
            {
              'peerId': 'peer-sender',
              'role': 'writer',
              'publicKey': 'pk-sender',
            },
          ],
          'createdBy': 'peer-admin',
          'createdAt': '2026-04-05T12:00:00.000Z',
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': '2026-04-05T12:21:00.000Z',
      });

      await Future.delayed(const Duration(milliseconds: 50));

      final group = await groupRepo.getGroup('group-1');
      expect(group!.name, 'Test Group');
      expect(group.description, isNull);
      expect(group.avatarBlobId, isNull);
      expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      expect(msgRepo.count, 0);
    });

    test(
      'older group_metadata_updated cannot roll back a newer metadata state after restart',
      () async {
        await saveTrustedAdminMember();
        bridge.responses['payload.verify'] = {'ok': true, 'valid': true};
        final newerListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        newerListener.start(sourceController.stream);

        final newerUpdatedAt = DateTime.parse('2026-04-05T12:30:00.000Z');
        final newerConfig = buildMetadataConfig(
          updatedAt: newerUpdatedAt,
          name: 'Newest Name',
          description: 'Newest description',
        );
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': jsonEncode(
            signedMetadataSystemPayload(
              updatedAt: newerUpdatedAt,
              groupConfig: newerConfig,
            ),
          ),
          'timestamp': newerUpdatedAt.toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));
        newerListener.dispose();

        final persistedAfterNewer = await groupRepo.getGroup('group-1');
        expect(persistedAfterNewer!.name, 'Newest Name');
        expect(persistedAfterNewer.lastMetadataEventAt, newerUpdatedAt.toUtc());

        final restartedListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        restartedListener.start(sourceController.stream);

        final olderUpdatedAt = DateTime.parse('2026-04-05T12:10:00.000Z');
        final olderConfig = buildMetadataConfig(
          updatedAt: olderUpdatedAt,
          name: 'Older Name',
          description: 'Older description',
        );
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': jsonEncode(
            signedMetadataSystemPayload(
              updatedAt: olderUpdatedAt,
              groupConfig: olderConfig,
            ),
          ),
          'timestamp': olderUpdatedAt.toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final finalGroup = await groupRepo.getGroup('group-1');
        expect(finalGroup!.name, 'Newest Name');
        expect(finalGroup.description, 'Newest description');
        expect(finalGroup.lastMetadataEventAt, newerUpdatedAt.toUtc());

        restartedListener.dispose();
      },
    );

    test(
      'duplicate member_added keeps one canonical member state and one UI stream event',
      () async {
        listener.start(sourceController.stream);

        final emittedMessages = <GroupMessage>[];
        final subscription = listener.groupMessageStream.listen(
          emittedMessages.add,
        );

        final sysText = jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': 'peer-charlie',
            'username': 'Charlie',
            'role': 'admin',
            'publicKey': 'pk-charlie',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
              {
                'peerId': 'peer-charlie',
                'role': 'admin',
                'publicKey': 'pk-charlie',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        final duplicateEvent = {
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        };

        sourceController.add(duplicateEvent);
        sourceController.add(duplicateEvent);

        await Future.delayed(const Duration(milliseconds: 50));

        final members = await groupRepo.getMembers('group-1');
        final charlies = members
            .where((member) => member.peerId == 'peer-charlie')
            .toList();

        expect(charlies, hasLength(1));
        expect(charlies.single.role, MemberRole.admin);
        expect(emittedMessages, hasLength(1));
        expect(emittedMessages.single.text, 'Admin added Charlie');
        expect(emittedMessages.single.senderPeerId, 'peer-admin');
        expect(msgRepo.count, 1);

        await subscription.cancel();
      },
    );

    test(
      'GM-027 ignores invalid member_added and members_added payloads without creating a ghost',
      () async {
        listener.start(sourceController.stream);

        final emittedMessages = <GroupMessage>[];
        final subscription = listener.groupMessageStream.listen(
          emittedMessages.add,
        );
        final eventAt = DateTime.utc(2026, 5, 11, 10, 15);
        final invalidMember = {
          'peerId': 'peer-gm027-ghost',
          'username': 'Ghost',
          'role': 'writer',
        };
        final validConfigMember = {
          'peerId': 'peer-sender',
          'username': 'Sender',
          'role': 'writer',
          'publicKey': 'pk-sender',
          'mlKemPublicKey': 'mlkem-sender',
        };
        final baseConfig = {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {
              'peerId': 'peer-admin',
              'username': 'Admin',
              'role': 'admin',
              'publicKey': 'pk-admin',
              'mlKemPublicKey': 'mlkem-admin',
            },
            validConfigMember,
            invalidMember,
          ],
          'createdBy': 'peer-admin',
          'createdAt': initialGroupCreatedAt.toIso8601String(),
        };

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': jsonEncode({
            '__sys': 'member_added',
            'eventAt': eventAt.toIso8601String(),
            'member': invalidMember,
            'groupConfig': baseConfig,
          }),
          'timestamp': eventAt.toIso8601String(),
          'messageId': 'gm027-invalid-member-added',
        });
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': jsonEncode({
            '__sys': 'members_added',
            'eventAt': eventAt
                .add(const Duration(seconds: 1))
                .toIso8601String(),
            'members': [invalidMember],
            'groupConfig': baseConfig,
          }),
          'timestamp': eventAt
              .add(const Duration(seconds: 1))
              .toIso8601String(),
          'messageId': 'gm027-invalid-members-added',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(
          await groupRepo.getMember('group-1', 'peer-gm027-ghost'),
          isNull,
        );
        expect(emittedMessages, isEmpty);
        expect(msgRepo.count, 0);

        final updateConfigMessages = bridge.sentMessages
            .map((message) => jsonDecode(message) as Map<String, dynamic>)
            .where((message) => message['cmd'] == 'group:updateConfig')
            .toList(growable: false);
        expect(updateConfigMessages, hasLength(2));
        for (final updateConfigMessage in updateConfigMessages) {
          final groupConfig =
              updateConfigMessage['payload']['groupConfig']
                  as Map<String, dynamic>;
          final configMembers = (groupConfig['members'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          expect(
            configMembers.map((member) => member['peerId']),
            isNot(contains('peer-gm027-ghost')),
          );
          expect(configMembers.map((member) => member['peerId']).toSet(), {
            'peer-admin',
            'peer-sender',
          });
        }

        await subscription.cancel();
      },
    );

    test(
      'GM-028 ignores empty PeerId member_added and members_added before config install',
      () async {
        listener.start(sourceController.stream);

        final emittedMessages = <GroupMessage>[];
        final subscription = listener.groupMessageStream.listen(
          emittedMessages.add,
        );
        final eventAt = DateTime.utc(2026, 5, 11, 10, 45);
        final blankMember = {
          'peerId': '   ',
          'username': 'Blank Peer',
          'role': 'writer',
          'publicKey': 'pk-gm028-blank',
          'mlKemPublicKey': 'mlkem-gm028-blank',
          'devices': [
            {
              'deviceId': 'gm028-blank-device',
              'transportPeerId': 'gm028-blank-device',
              'deviceSigningPublicKey': 'pk-gm028-blank-device',
              'mlKemPublicKey': 'mlkem-gm028-blank-device',
              'keyPackageId': 'kp-gm028-blank-device',
              'keyPackagePublicMaterial': 'public-kp-gm028-blank-device',
              'status': 'active',
            },
          ],
        };
        final validConfigMember = {
          'peerId': 'peer-sender',
          'username': 'Sender',
          'role': 'writer',
          'publicKey': 'pk-sender',
          'mlKemPublicKey': 'mlkem-sender',
        };
        final baseConfig = {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {
              'peerId': 'peer-admin',
              'username': 'Admin',
              'role': 'admin',
              'publicKey': 'pk-admin',
              'mlKemPublicKey': 'mlkem-admin',
            },
            blankMember,
            validConfigMember,
          ],
          'createdBy': 'peer-admin',
          'createdAt': initialGroupCreatedAt.toIso8601String(),
          groupConfigStateHashField: 'stale-gm028-hash',
        };

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': jsonEncode({
            '__sys': 'member_added',
            'eventAt': eventAt.toIso8601String(),
            'member': blankMember,
            'groupConfig': baseConfig,
          }),
          'timestamp': eventAt.toIso8601String(),
          'messageId': 'gm028-empty-peer-member-added',
        });
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': jsonEncode({
            '__sys': 'members_added',
            'eventAt': eventAt
                .add(const Duration(seconds: 1))
                .toIso8601String(),
            'members': [blankMember],
            'groupConfig': baseConfig,
          }),
          'timestamp': eventAt
              .add(const Duration(seconds: 1))
              .toIso8601String(),
          'messageId': 'gm028-empty-peer-members-added',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final members = await groupRepo.getMembers('group-1');
        expect(
          members.where((member) => member.peerId.trim().isEmpty),
          isEmpty,
        );
        expect(await groupRepo.getMember('group-1', ''), isNull);
        expect(await groupRepo.getMember('group-1', '   '), isNull);
        expect(emittedMessages, isEmpty);
        expect(msgRepo.count, 0);

        final updateConfigMessages = bridge.sentMessages
            .map((message) => jsonDecode(message) as Map<String, dynamic>)
            .where((message) => message['cmd'] == 'group:updateConfig')
            .toList(growable: false);
        expect(updateConfigMessages, hasLength(2));
        for (final updateConfigMessage in updateConfigMessages) {
          final groupConfig =
              updateConfigMessage['payload']['groupConfig']
                  as Map<String, dynamic>;
          expect(
            isGroupConfigStateHashValid(
              groupId: 'group-1',
              groupConfig: groupConfig,
            ),
            isTrue,
          );
          final configMembers = (groupConfig['members'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          expect(
            configMembers.map((member) => member['peerId']),
            isNot(contains('   ')),
          );
          expect(
            configMembers.where(
              (member) => (member['peerId'] as String?)?.trim().isEmpty ?? true,
            ),
            isEmpty,
          );
          expect(configMembers.map((member) => member['peerId']).toSet(), {
            'peer-admin',
            'peer-sender',
          });
        }

        await subscription.cancel();
      },
    );

    test(
      'GM-022 member_added syncs one active Charlie config entry from duplicate snapshot',
      () async {
        listener.start(sourceController.stream);
        final eventAt = DateTime.utc(2026, 5, 11, 8, 30);

        final sysText = jsonEncode({
          '__sys': 'member_added',
          'eventAt': eventAt.toIso8601String(),
          'member': {
            'peerId': 'peer-charlie',
            'username': 'Charlie',
            'role': 'writer',
            'publicKey': 'pk-charlie',
            'mlKemPublicKey': 'mlkem-charlie',
            'devices': [
              {
                'deviceId': 'charlie-device',
                'transportPeerId': 'charlie-device',
                'deviceSigningPublicKey': 'pk-charlie',
                'mlKemPublicKey': 'mlkem-charlie-device',
                'keyPackageId': 'kp-charlie-active',
                'keyPackagePublicMaterial': 'public-kp-charlie-active',
                'status': 'active',
              },
            ],
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-charlie',
                'username': 'Charlie',
                'role': 'writer',
                'publicKey': 'pk-charlie',
                'mlKemPublicKey': 'mlkem-charlie',
                'devices': [
                  {
                    'deviceId': 'charlie-device',
                    'transportPeerId': 'charlie-device',
                    'deviceSigningPublicKey': 'pk-charlie',
                    'mlKemPublicKey': 'mlkem-charlie-device',
                    'keyPackageId': 'kp-charlie-stale',
                    'keyPackagePublicMaterial': 'public-kp-charlie-stale',
                    'status': 'revoked',
                    'revokedAt': eventAt
                        .subtract(const Duration(minutes: 1))
                        .toIso8601String(),
                  },
                ],
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
              {
                'peerId': 'peer-charlie',
                'username': 'Charlie',
                'role': 'writer',
                'publicKey': 'pk-charlie',
                'mlKemPublicKey': 'mlkem-charlie',
                'devices': [
                  {
                    'deviceId': 'charlie-device',
                    'transportPeerId': 'charlie-device',
                    'deviceSigningPublicKey': 'pk-charlie',
                    'mlKemPublicKey': 'mlkem-charlie-device',
                    'keyPackageId': 'kp-charlie-active',
                    'keyPackagePublicMaterial': 'public-kp-charlie-active',
                    'status': 'active',
                  },
                ],
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': initialGroupCreatedAt.toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': eventAt.toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final updateConfigMessages = bridge.sentMessages
            .map((message) => jsonDecode(message) as Map<String, dynamic>)
            .where((message) => message['cmd'] == 'group:updateConfig')
            .toList(growable: false);
        expect(updateConfigMessages, hasLength(1));
        final groupConfig =
            updateConfigMessages.single['payload']['groupConfig']
                as Map<String, dynamic>;
        final configMembers = (groupConfig['members'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final configPeerIds = configMembers
            .map((member) => member['peerId'] as String?)
            .whereType<String>()
            .toList();
        expect(configPeerIds.where((peerId) => peerId == 'peer-charlie'), [
          'peer-charlie',
        ]);
        final charlieConfig = configMembers.singleWhere(
          (member) => member['peerId'] == 'peer-charlie',
        );
        final configDevices = (charlieConfig['devices'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(configDevices, hasLength(1));
        expect(configDevices.single['keyPackageId'], 'kp-charlie-active');
        expect(jsonEncode(groupConfig), isNot(contains('kp-charlie-stale')));

        final members = await groupRepo.getMembers('group-1');
        final charlieRows = members
            .where((member) => member.peerId == 'peer-charlie')
            .toList(growable: false);
        expect(charlieRows, hasLength(1));
        expect(charlieRows.single.activeDevices, hasLength(1));
        expect(
          charlieRows.single.activeDevices.single.keyPackageId,
          'kp-charlie-active',
        );
      },
    );

    test(
      'GM-023 member_added sync selects active Charlie after inactive shadow',
      () async {
        listener.start(sourceController.stream);
        final eventAt = DateTime.utc(2026, 5, 11, 9, 15);

        final sysText = jsonEncode({
          '__sys': 'member_added',
          'eventAt': eventAt.toIso8601String(),
          'member': {
            'peerId': 'peer-charlie',
            'username': 'Charlie',
            'role': 'writer',
            'publicKey': 'pk-charlie',
            'mlKemPublicKey': 'mlkem-charlie',
            'devices': [
              {
                'deviceId': 'charlie-device',
                'transportPeerId': 'charlie-device',
                'deviceSigningPublicKey': 'pk-charlie',
                'mlKemPublicKey': 'mlkem-charlie-device',
                'keyPackageId': 'kp-charlie-active',
                'keyPackagePublicMaterial': 'public-kp-charlie-active',
                'status': 'active',
              },
            ],
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-charlie',
                'username': 'Charlie',
                'role': 'writer',
                'publicKey': 'pk-charlie',
                'mlKemPublicKey': 'mlkem-charlie',
                'devices': [
                  {
                    'deviceId': 'charlie-device',
                    'transportPeerId': 'charlie-device',
                    'deviceSigningPublicKey': 'pk-charlie',
                    'mlKemPublicKey': 'mlkem-charlie-device',
                    'keyPackageId': 'kp-charlie-inactive',
                    'keyPackagePublicMaterial': 'public-kp-charlie-inactive',
                    'status': 'revoked',
                    'revokedAt': eventAt
                        .subtract(const Duration(minutes: 1))
                        .toIso8601String(),
                  },
                ],
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
              {
                'peerId': 'peer-charlie',
                'username': 'Charlie',
                'role': 'writer',
                'publicKey': 'pk-charlie',
                'mlKemPublicKey': 'mlkem-charlie',
                'devices': [
                  {
                    'deviceId': 'charlie-device',
                    'transportPeerId': 'charlie-device',
                    'deviceSigningPublicKey': 'pk-charlie',
                    'mlKemPublicKey': 'mlkem-charlie-device',
                    'keyPackageId': 'kp-charlie-active',
                    'keyPackagePublicMaterial': 'public-kp-charlie-active',
                    'status': 'active',
                  },
                ],
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': initialGroupCreatedAt.toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': eventAt.toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final updateConfigMessages = bridge.sentMessages
            .map((message) => jsonDecode(message) as Map<String, dynamic>)
            .where((message) => message['cmd'] == 'group:updateConfig')
            .toList(growable: false);
        expect(updateConfigMessages, hasLength(1));
        final groupConfig =
            updateConfigMessages.single['payload']['groupConfig']
                as Map<String, dynamic>;
        final configMembers = (groupConfig['members'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(
          configMembers
              .map((member) => member['peerId'])
              .where((peerId) => peerId == 'peer-charlie'),
          ['peer-charlie'],
        );
        final charlieConfig = configMembers.singleWhere(
          (member) => member['peerId'] == 'peer-charlie',
        );
        final configDevices = (charlieConfig['devices'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(configDevices, hasLength(1));
        expect(configDevices.single['status'], 'active');
        expect(configDevices.single['keyPackageId'], 'kp-charlie-active');
        expect(jsonEncode(groupConfig), isNot(contains('kp-charlie-inactive')));

        final members = await groupRepo.getMembers('group-1');
        final charlieRows = members
            .where((member) => member.peerId == 'peer-charlie')
            .toList(growable: false);
        expect(charlieRows, hasLength(1));
        expect(charlieRows.single.activeDevices, hasLength(1));
        expect(
          charlieRows.single.activeDevices.single.keyPackageId,
          'kp-charlie-active',
        );
      },
    );

    test(
      'older member_removed cannot roll back a newer added admin state after restart',
      () async {
        final newerListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        newerListener.start(sourceController.stream);

        const newerAddAt = '2026-04-05T12:00:02.000Z';
        final newerAdd = jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': 'peer-charlie',
            'username': 'Charlie',
            'role': 'admin',
            'publicKey': 'pk-charlie',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
              {
                'peerId': 'peer-charlie',
                'role': 'admin',
                'publicKey': 'pk-charlie',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': newerAdd,
          'timestamp': newerAddAt,
        });

        await Future.delayed(const Duration(milliseconds: 50));
        newerListener.dispose();

        final persistedAfterAdd = await groupRepo.getGroup('group-1');
        expect(
          persistedAfterAdd!.lastMembershipEventAt,
          DateTime.parse(newerAddAt).toUtc(),
        );
        final charlieAfterAdd = await groupRepo.getMember(
          'group-1',
          'peer-charlie',
        );
        expect(charlieAfterAdd, isNotNull);
        expect(charlieAfterAdd!.role, MemberRole.admin);

        final restartedListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        restartedListener.start(sourceController.stream);

        final olderRemove = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-charlie', 'username': 'Charlie'},
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': olderRemove,
          'timestamp': '2026-04-05T12:00:01.000Z',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final charlieAfterStaleRemove = await groupRepo.getMember(
          'group-1',
          'peer-charlie',
        );
        expect(charlieAfterStaleRemove, isNotNull);
        expect(charlieAfterStaleRemove!.role, MemberRole.admin);
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(1),
        );

        restartedListener.dispose();
      },
    );

    test(
      'member_added retries once using incoming groupConfig snapshot and then succeeds',
      () async {
        bridge = SequencedUpdateConfigBridge([
          (_) async => throw Exception('first update failed'),
          (_) async => jsonEncode({'ok': true}),
        ]);
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        listener.start(sourceController.stream);

        final sysText = jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': 'peer-charlie',
            'username': 'Charlie Local',
            'role': 'writer',
            'publicKey': 'pk-charlie',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
              {
                'peerId': 'peer-charlie',
                'username': 'Charlie Snapshot',
                'role': 'writer',
                'publicKey': 'pk-charlie',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final charlie = await groupRepo.getMember('group-1', 'peer-charlie');
        expect(charlie, isNotNull);
        expect(charlie!.username, 'Charlie Snapshot');

        final updateConfigCalls = bridge.commandLog
            .where((command) => command == 'group:updateConfig')
            .length;
        expect(updateConfigCalls, 2);

        final secondUpdate =
            jsonDecode(
                  bridge.sentMessages.where((message) {
                    final parsed = jsonDecode(message) as Map<String, dynamic>;
                    return parsed['cmd'] == 'group:updateConfig';
                  }).last,
                )
                as Map<String, dynamic>;
        final groupConfig =
            secondUpdate['payload']['groupConfig'] as Map<String, dynamic>;
        final members = groupConfig['members'] as List<dynamic>;
        final charlieConfig = members.cast<Map<String, dynamic>>().firstWhere(
          (member) => member['peerId'] == 'peer-charlie',
        );
        expect(charlieConfig['username'], 'Charlie Snapshot');
      },
    );

    test('members_added saves all members and calls updateConfig', () async {
      listener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'members_added',
        'members': [
          {
            'peerId': 'peer-dave',
            'username': 'Dave',
            'role': 'writer',
            'publicKey': 'pk-dave',
          },
          {
            'peerId': 'peer-eve',
            'username': 'Eve',
            'role': 'writer',
            'publicKey': 'pk-eve',
          },
        ],
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-admin', 'role': 'admin', 'publicKey': 'pk-admin'},
            {
              'peerId': 'peer-sender',
              'role': 'writer',
              'publicKey': 'pk-sender',
            },
            {'peerId': 'peer-dave', 'role': 'writer', 'publicKey': 'pk-dave'},
            {'peerId': 'peer-eve', 'role': 'writer', 'publicKey': 'pk-eve'},
          ],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      // Both members saved
      final dave = await groupRepo.getMember('group-1', 'peer-dave');
      expect(dave, isNotNull);
      expect(dave!.username, 'Dave');
      final eve = await groupRepo.getMember('group-1', 'peer-eve');
      expect(eve, isNotNull);
      expect(eve!.username, 'Eve');

      // Config updated once
      final updateConfigCalls = bridge.commandLog
          .where((c) => c == 'group:updateConfig')
          .length;
      expect(updateConfigCalls, 1);

      expect(msgRepo.count, 1);
      final saved = await msgRepo.getLatestMessage('group-1');
      expect(saved, isNotNull);
      expect(saved!.text, 'Admin added Dave and Eve');
    });

    test('member_joined saves a durable join timeline event', () async {
      listener.start(sourceController.stream);

      final messages = <GroupMessage>[];
      final subscription = listener.groupMessageStream.listen(messages.add);

      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-charlie',
          username: 'Charlie',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final sysText = jsonEncode({
        '__sys': 'member_joined',
        'member': {'peerId': 'peer-charlie', 'username': 'Charlie'},
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-charlie',
        'senderUsername': 'Charlie',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(messages, hasLength(1));
      expect(messages.single.text, 'Charlie joined the group');
      expect(messages.single.senderPeerId, 'peer-charlie');
      expect(messages.single.senderUsername, 'Charlie');
      expect(msgRepo.count, 1);
      final saved = await msgRepo.getLatestMessage('group-1');
      expect(saved, isNotNull);
      expect(saved!.text, 'Charlie joined the group');

      await subscription.cancel();
    });

    test('member_joined marks invite delivery status as joined', () async {
      final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();
      listener.dispose();
      listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        inviteDeliveryAttemptRepo: inviteStatusRepo,
      );
      listener.start(sourceController.stream);

      await inviteStatusRepo.saveAttempt(
        GroupInviteDeliveryAttempt(
          groupId: 'group-1',
          peerId: 'peer-charlie',
          username: 'Charlie',
          status: GroupInviteDeliveryStatus.needsResend,
          attemptedAt: DateTime.utc(2026, 5, 7, 12),
          updatedAt: DateTime.utc(2026, 5, 7, 12),
          lastError: 'send_failed',
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-charlie',
          username: 'Charlie',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-charlie',
        'senderUsername': 'Charlie',
        'keyEpoch': 0,
        'text': jsonEncode({
          '__sys': 'member_joined',
          'member': {'peerId': 'peer-charlie', 'username': 'Charlie'},
        }),
        'timestamp': '2026-05-07T12:05:00.000Z',
      });

      await Future.delayed(const Duration(milliseconds: 50));

      final attempt = await inviteStatusRepo.getAttempt(
        groupId: 'group-1',
        peerId: 'peer-charlie',
      );
      expect(attempt!.status, GroupInviteDeliveryStatus.joined);
      expect(attempt.lastError, isNull);
    });

    test(
      'member_joined replay preserves read state for durable timeline event',
      () async {
        listener.start(sourceController.stream);

        final messages = <GroupMessage>[];
        final subscription = listener.groupMessageStream.listen(messages.add);

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        final eventAt = DateTime.utc(2026, 4, 5, 12, 5);
        final sysText = jsonEncode({
          '__sys': 'member_joined',
          'member': {'peerId': 'peer-charlie', 'username': 'Charlie'},
        });
        final event = <String, dynamic>{
          'groupId': 'group-1',
          'senderId': 'peer-charlie',
          'senderUsername': 'Charlie',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': eventAt.toIso8601String(),
        };

        sourceController.add(event);
        await Future.delayed(const Duration(milliseconds: 50));

        await msgRepo.markAsRead('group-1');
        final readMessage = await msgRepo.getLatestMessage('group-1');
        expect(readMessage, isNotNull);
        expect(readMessage!.readAt, isNotNull);

        sourceController.add(event);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(msgRepo.count, 1);
        final replayed = await msgRepo.getLatestMessage('group-1');
        expect(replayed!.readAt, readMessage.readAt);
        expect(messages, hasLength(2));
        expect(messages.last.readAt, readMessage.readAt);

        await subscription.cancel();
      },
    );

    test('unauthorized members_added is ignored', () async {
      listener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'members_added',
        'members': [
          {
            'peerId': 'peer-dave',
            'username': 'Dave',
            'role': 'writer',
            'publicKey': 'pk-dave',
          },
          {
            'peerId': 'peer-eve',
            'username': 'Eve',
            'role': 'writer',
            'publicKey': 'pk-eve',
          },
        ],
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-admin', 'role': 'admin', 'publicKey': 'pk-admin'},
            {
              'peerId': 'peer-sender',
              'role': 'writer',
              'publicKey': 'pk-sender',
            },
            {'peerId': 'peer-dave', 'role': 'writer', 'publicKey': 'pk-dave'},
            {'peerId': 'peer-eve', 'role': 'writer', 'publicKey': 'pk-eve'},
          ],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(await groupRepo.getMember('group-1', 'peer-dave'), isNull);
      expect(await groupRepo.getMember('group-1', 'peer-eve'), isNull);
      expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      expect(msgRepo.count, 0);
    });

    test(
      'members_added retries once using incoming groupConfig snapshot and then succeeds',
      () async {
        bridge = SequencedUpdateConfigBridge([
          (_) async => throw Exception('first update failed'),
          (_) async => jsonEncode({'ok': true}),
        ]);
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        listener.start(sourceController.stream);

        final sysText = jsonEncode({
          '__sys': 'members_added',
          'members': [
            {
              'peerId': 'peer-dave',
              'username': 'Dave Local',
              'role': 'writer',
              'publicKey': 'pk-dave',
            },
            {
              'peerId': 'peer-eve',
              'username': 'Eve Local',
              'role': 'writer',
              'publicKey': 'pk-eve',
            },
          ],
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
              {
                'peerId': 'peer-dave',
                'username': 'Dave Snapshot',
                'role': 'writer',
                'publicKey': 'pk-dave',
              },
              {
                'peerId': 'peer-eve',
                'username': 'Eve Snapshot',
                'role': 'writer',
                'publicKey': 'pk-eve',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final dave = await groupRepo.getMember('group-1', 'peer-dave');
        final eve = await groupRepo.getMember('group-1', 'peer-eve');
        expect(dave, isNotNull);
        expect(eve, isNotNull);
        expect(dave!.username, 'Dave Snapshot');
        expect(eve!.username, 'Eve Snapshot');

        final updateConfigCalls = bridge.commandLog
            .where((command) => command == 'group:updateConfig')
            .length;
        expect(updateConfigCalls, 2);

        final secondUpdate =
            jsonDecode(
                  bridge.sentMessages.where((message) {
                    final parsed = jsonDecode(message) as Map<String, dynamic>;
                    return parsed['cmd'] == 'group:updateConfig';
                  }).last,
                )
                as Map<String, dynamic>;
        final groupConfig =
            secondUpdate['payload']['groupConfig'] as Map<String, dynamic>;
        final members = groupConfig['members'] as List<dynamic>;
        final daveConfig = members.cast<Map<String, dynamic>>().firstWhere(
          (member) => member['peerId'] == 'peer-dave',
        );
        final eveConfig = members.cast<Map<String, dynamic>>().firstWhere(
          (member) => member['peerId'] == 'peer-eve',
        );
        expect(daveConfig['username'], 'Dave Snapshot');
        expect(eveConfig['username'], 'Eve Snapshot');
      },
    );

    test(
      'concurrent system messages execute sequentially across full pipeline',
      () async {
        final firstUpdate = Completer<String>();
        final secondUpdateStarted = Completer<void>();

        bridge = SequencedUpdateConfigBridge([
          (_) => firstUpdate.future,
          (_) async {
            secondUpdateStarted.complete();
            return jsonEncode({'ok': true});
          },
        ]);
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        listener.start(sourceController.stream);

        final firstMessage = jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': 'peer-alice',
            'username': 'Alice',
            'role': 'writer',
            'publicKey': 'pk-alice',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
              {
                'peerId': 'peer-alice',
                'role': 'writer',
                'publicKey': 'pk-alice',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });
        final secondMessage = jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': 'peer-bob',
            'username': 'Bob',
            'role': 'writer',
            'publicKey': 'pk-bob',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
              {
                'peerId': 'peer-alice',
                'role': 'writer',
                'publicKey': 'pk-alice',
              },
              {'peerId': 'peer-bob', 'role': 'writer', 'publicKey': 'pk-bob'},
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': firstMessage,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': secondMessage,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(1),
        );
        expect(await groupRepo.getMember('group-1', 'peer-alice'), isNotNull);
        expect(await groupRepo.getMember('group-1', 'peer-bob'), isNull);
        expect(secondUpdateStarted.isCompleted, isFalse);

        firstUpdate.complete(jsonEncode({'ok': true}));
        await Future.delayed(const Duration(milliseconds: 50));

        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(2),
        );
        expect(await groupRepo.getMember('group-1', 'peer-bob'), isNotNull);
        expect(secondUpdateStarted.isCompleted, isTrue);
      },
    );

    test(
      'member_added emits readable timeline event on groupMessageStream',
      () async {
        listener.start(sourceController.stream);

        final messages = <GroupMessage>[];
        final subscription = listener.groupMessageStream.listen(messages.add);

        final sysText = jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': 'peer-charlie',
            'username': 'Charlie',
            'role': 'writer',
            'publicKey': 'pk-charlie',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(messages, hasLength(1));
        expect(messages.single.text, 'Admin added Charlie');
        expect(messages.single.senderPeerId, 'peer-admin');
        expect(messages.single.senderUsername, 'Admin');
        expect(messages.single.isIncoming, isTrue);
        expect(msgRepo.count, 1);
        final saved = await msgRepo.getLatestMessage('group-1');
        expect(saved, isNotNull);
        expect(saved!.text, 'Admin added Charlie');

        await subscription.cancel();
      },
    );

    test(
      'system message without bridge falls through as regular message',
      () async {
        // Create listener without bridge
        final noBridgeListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
        );
        noBridgeListener.start(sourceController.stream);

        final sysText = jsonEncode({
          '__sys': 'member_added',
          'member': {'peerId': 'peer-charlie'},
          'groupConfig': {},
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        // Without bridge, treated as regular message and saved
        expect(msgRepo.count, 1);

        noBridgeListener.dispose();
      },
    );
  });

  group('member_removed system messages', () {
    test(
      'member_removed removes other member and calls updateConfig',
      () async {
        // Verify the member exists first
        final before = await groupRepo.getMember('group-1', 'peer-sender');
        expect(before, isNotNull);

        listener.start(sourceController.stream);

        final sysText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-sender', 'username': 'Sender'},
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(msgRepo.count, 1);
        final saved = await msgRepo.getLatestMessage('group-1');
        expect(saved, isNotNull);
        expect(saved!.text, 'Admin removed Sender');
        expect(
          saved.id.startsWith('sys-member_removed:group-1:peer-sender:'),
          isTrue,
        );

        // Member should be removed from the group repo
        final after = await groupRepo.getMember('group-1', 'peer-sender');
        expect(after, isNull);

        // Bridge should have received group:updateConfig
        expect(bridge.commandLog, contains('group:updateConfig'));
      },
    );

    test(
      'GM-032 all-members-removed snapshot dissolves, leaves, and preserves history',
      () async {
        final historicalAt = DateTime.utc(2026, 4, 5, 11, 58, 0);
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'gm032-history',
            groupId: 'group-1',
            senderPeerId: 'peer-sender',
            senderUsername: 'Sender',
            text: 'GM-032 historical message',
            timestamp: historicalAt,
            status: 'sent',
            isIncoming: true,
            createdAt: historicalAt,
          ),
        );

        final removedAt = DateTime.utc(2026, 4, 5, 12, 0, 0);
        listener.start(sourceController.stream);

        sourceController.add({
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
              'members': <Map<String, dynamic>>[],
              'createdBy': 'peer-admin',
              'createdAt': initialGroupCreatedAt.toIso8601String(),
            },
          }),
          'timestamp': removedAt.toIso8601String(),
          'messageId': 'gm032-all-members-removed',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final group = await groupRepo.getGroup('group-1');
        expect(group, isNotNull);
        expect(group!.isDissolved, isTrue);
        expect(group.dissolvedAt, removedAt);
        expect(group.dissolvedBy, 'peer-admin');
        expect(await groupRepo.getMembers('group-1'), isEmpty);
        expect(bridge.commandLog, contains('group:updateConfig'));
        expect(bridge.commandLog, contains('group:leave'));

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': 'GM-032 after empty membership',
          'timestamp': removedAt.toIso8601String(),
          'messageId': 'gm032-after-empty-membership',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final messages = await msgRepo.getMessagesPage('group-1');
        expect(
          messages.map((message) => message.text),
          contains('GM-032 historical message'),
        );
        expect(
          messages.map((message) => message.text),
          contains('Admin removed Sender'),
        );
        expect(
          messages.map((message) => message.text),
          isNot(contains('GM-032 after empty membership')),
        );
      },
    );

    test(
      'GM-013 listener preserves member_removed cutoff and emits after-cutoff rejection',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        addTearDown(() => debugSetFlowEventSink(null));

        final emitted = <GroupMessage>[];
        final subscription = listener.groupMessageStream.listen(emitted.add);
        addTearDown(subscription.cancel);

        final removedAt = DateTime.utc(2026, 4, 5, 12, 0, 0);
        final beforeSentAt = removedAt.subtract(
          const Duration(milliseconds: 1),
        );
        listener.start(sourceController.stream);

        final sysText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-sender', 'username': 'Sender'},
          'removedAt': removedAt.toIso8601String(),
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'username': 'Admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': initialGroupCreatedAt.toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': removedAt.toIso8601String(),
          'messageId': 'gm013-member-removed',
        });

        await Future.delayed(const Duration(milliseconds: 50));
        expect(await groupRepo.getMember('group-1', 'peer-sender'), isNull);
        expect(
          await msgRepo.getLatestRemovalTimestampForSender(
            'group-1',
            'peer-sender',
          ),
          removedAt,
        );

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'text': 'GM-013 before cutoff',
          'timestamp': beforeSentAt.toIso8601String(),
          'messageId': 'gm013-listener-before-cutoff',
        });
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'text': 'GM-013 at cutoff',
          'timestamp': removedAt.toIso8601String(),
          'messageId': 'gm013-listener-at-cutoff',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(
          (await msgRepo.getMessagesPage(
            'group-1',
          )).where((message) => message.text == 'GM-013 before cutoff'),
          hasLength(1),
        );
        expect(await msgRepo.getMessage('gm013-listener-at-cutoff'), isNull);
        expect(
          emitted.where((message) => message.text == 'GM-013 before cutoff'),
          hasLength(1),
        );
        expect(
          emitted.where((message) => message.text == 'GM-013 at cutoff'),
          isEmpty,
        );

        final rejectionEvents = flowEvents
            .where(
              (event) =>
                  event['event'] ==
                  'GROUP_HANDLE_INCOMING_MSG_REMOVED_AFTER_CUTOFF',
            )
            .toList(growable: false);
        expect(rejectionEvents, hasLength(1));
        final details =
            rejectionEvents.single['details'] as Map<String, dynamic>;
        expect(details['cutoffAt'], removedAt.toIso8601String());
      },
    );

    test(
      'equal-watermark group_metadata_updated retries avatar recovery when avatarPath is still missing',
      () async {
        await saveTrustedAdminMember();
        bridge.responses['payload.verify'] = {'ok': true, 'valid': true};
        final updatedAt = DateTime.parse('2026-04-05T12:20:00.000Z');
        await groupRepo.updateGroup(
          testGroup.copyWith(
            avatarBlobId: 'blob-1',
            avatarMime: 'image/jpeg',
            avatarPath: null,
            lastMetadataEventAt: updatedAt.toUtc(),
          ),
        );

        var downloadCalls = 0;
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          downloadGroupAvatarFn:
              ({
                required dynamic bridge,
                required String groupId,
                required String blobId,
              }) async {
                downloadCalls++;
                return 'media/group_avatars/$groupId.jpg';
              },
        );
        listener.start(sourceController.stream);

        final groupConfig = buildMetadataConfig(
          updatedAt: updatedAt,
          name: 'Recovered Avatar Group',
          avatarBlobId: 'blob-1',
          avatarMime: 'image/jpeg',
        );
        final sysText = jsonEncode(
          signedMetadataSystemPayload(
            updatedAt: updatedAt,
            groupConfig: groupConfig,
          ),
        );

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': updatedAt.toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final updatedGroup = await groupRepo.getGroup('group-1');
        expect(updatedGroup, isNotNull);
        expect(updatedGroup!.avatarPath, 'media/group_avatars/group-1.jpg');
        expect(downloadCalls, 1);
      },
    );

    test('unauthorized member_removed is ignored', () async {
      listener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'member_removed',
        'member': {'peerId': 'peer-admin', 'username': 'Admin'},
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {
              'peerId': 'peer-sender',
              'role': 'writer',
              'publicKey': 'pk-sender',
            },
          ],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(await groupRepo.getGroup('group-1'), isNotNull);
      expect(await groupRepo.getMember('group-1', 'peer-sender'), isNotNull);
      expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      expect(msgRepo.count, 0);
    });

    test('replayed unauthorized member_removed is ignored', () async {
      final sysText = jsonEncode({
        '__sys': 'member_removed',
        'member': {'peerId': 'peer-admin', 'username': 'Admin'},
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {
              'peerId': 'peer-sender',
              'role': 'writer',
              'publicKey': 'pk-sender',
            },
          ],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      await listener.handleReplayEnvelope({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      expect(await groupRepo.getGroup('group-1'), isNotNull);
      expect(await groupRepo.getMember('group-1', 'peer-sender'), isNotNull);
      expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      expect(msgRepo.count, 0);
    });

    test(
      'member_removed emits CONFIG_SYNC_FAILED when both update attempts fail',
      () async {
        bridge = SequencedUpdateConfigBridge([
          (_) async => throw Exception('first update failed'),
          (_) async => throw Exception('second update failed'),
        ]);
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        listener.start(sourceController.stream);

        final sysText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-sender', 'username': 'Sender'},
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(await groupRepo.getMember('group-1', 'peer-sender'), isNull);
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(2),
        );
        expect(
          debugLogs.any(
            (line) => line.contains('"event":"CONFIG_SYNC_FAILED"'),
          ),
          isTrue,
        );
      },
    );

    test(
      'member_removed emits readable timeline event on groupMessageStream',
      () async {
        listener.start(sourceController.stream);

        final messages = <GroupMessage>[];
        final subscription = listener.groupMessageStream.listen(messages.add);

        final sysText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-sender', 'username': 'Sender'},
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(messages, hasLength(1));
        expect(messages.single.text, 'Admin removed Sender');
        expect(messages.single.senderPeerId, 'peer-admin');
        expect(messages.single.senderUsername, 'Admin');
        expect(messages.single.isIncoming, isTrue);
        expect(msgRepo.count, 1);
        final saved = await msgRepo.getLatestMessage('group-1');
        expect(saved, isNotNull);
        expect(saved!.text, 'Admin removed Sender');

        await subscription.cancel();
      },
    );

    test(
      'self-removal calls leaveGroup and emits on groupRemovedStream',
      () async {
        final selfJoinedAt = DateTime.utc(2026, 4, 5, 12);
        final removedAt = DateTime.utc(2026, 4, 5, 12, 0, 1);
        // Create a listener that knows its own peerId
        final selfListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
        );

        // Add self as a member of the group
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-self',
            username: 'Me',
            role: MemberRole.writer,
            joinedAt: selfJoinedAt,
          ),
        );
        await groupRepo.updateGroup(
          testGroup.copyWith(myRole: GroupRole.member),
        );

        selfListener.start(sourceController.stream);

        final removedGroups = <String>[];
        final sub = selfListener.groupRemovedStream.listen(removedGroups.add);

        final sysText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-self', 'username': 'Me'},
          'removedAt': removedAt.toIso8601String(),
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {'peerId': 'peer-admin', 'role': 'admin'},
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': removedAt.toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        // Bridge should have received group:leave
        expect(bridge.commandLog, contains('group:leave'));

        // Group should be deleted from local DB
        final group = await groupRepo.getGroup('group-1');
        expect(group, isNull);

        // groupRemovedStream should have emitted the group ID
        expect(removedGroups, ['group-1']);

        // No regular message saved
        expect(msgRepo.count, 0);

        await sub.cancel();
        selfListener.dispose();
      },
    );

    test(
      'ML-017 self-removal preserves local old history as read-only state',
      () async {
        final selfJoinedAt = DateTime.utc(2026, 4, 5, 12);
        final removedAt = DateTime.utc(2026, 4, 5, 12, 0, 1);
        final selfListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
        );

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-self',
            username: 'Me',
            role: MemberRole.writer,
            publicKey: 'pk-self',
            joinedAt: selfJoinedAt,
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 1,
            encryptedKey: 'key-before-removal',
            createdAt: selfJoinedAt,
          ),
        );
        await groupRepo.updateGroup(
          testGroup.copyWith(myRole: GroupRole.member),
        );
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'ml017-before-removal',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'ML-017 old local history',
            timestamp: selfJoinedAt.add(const Duration(seconds: 30)),
            status: 'delivered',
            isIncoming: true,
            createdAt: selfJoinedAt.add(const Duration(seconds: 30)),
          ),
        );

        selfListener.start(sourceController.stream);

        final removedGroups = <String>[];
        final sub = selfListener.groupRemovedStream.listen(removedGroups.add);

        final sysText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-self', 'username': 'Me'},
          'removedAt': removedAt.toIso8601String(),
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {'peerId': 'peer-admin', 'role': 'admin'},
            ],
            'createdBy': 'peer-admin',
            'createdAt': initialGroupCreatedAt.toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': removedAt.toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(
          bridge.commandLog.where((command) => command == 'group:leave'),
          hasLength(1),
        );
        expect(await groupRepo.getGroup('group-1'), isNotNull);
        expect(await groupRepo.getMember('group-1', 'peer-self'), isNull);
        expect(await groupRepo.getMember('group-1', 'peer-admin'), isNotNull);
        expect(await groupRepo.getLatestKey('group-1'), isNull);
        expect(removedGroups, ['group-1']);

        final retainedMessages = await msgRepo.getMessagesPage('group-1');
        expect(
          retainedMessages.map((message) => message.text),
          containsAll(['ML-017 old local history', 'Admin removed Me']),
        );

        await sub.cancel();
        selfListener.dispose();
      },
    );

    test(
      'RA-011 late self-removal leave completion repairs newer re-add topic',
      () async {
        final delayedBridge = _DelayedGroupLeaveBridge();
        bridge = delayedBridge;
        final selfJoinedAt = DateTime.utc(2026, 4, 5, 12);
        final removedAt = DateTime.utc(2026, 4, 5, 12, 0, 1);
        final readdAt = DateTime.utc(2026, 4, 5, 12, 0, 6);
        final selfListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: delayedBridge,
          getSelfPeerId: () async => 'peer-self',
        );

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-self',
            username: 'Me',
            role: MemberRole.writer,
            publicKey: 'pk-self-old',
            joinedAt: selfJoinedAt,
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 1,
            encryptedKey: 'key-before-removal',
            createdAt: selfJoinedAt,
          ),
        );
        await groupRepo.updateGroup(
          testGroup.copyWith(myRole: GroupRole.member),
        );
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'ra011-before-removal-history',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'RA-011 retained old history',
            timestamp: selfJoinedAt.add(const Duration(seconds: 30)),
            status: 'delivered',
            isIncoming: true,
            createdAt: selfJoinedAt.add(const Duration(seconds: 30)),
          ),
        );

        selfListener.start(sourceController.stream);

        final removedGroups = <String>[];
        final sub = selfListener.groupRemovedStream.listen(removedGroups.add);

        final sysText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-self', 'username': 'Me'},
          'removedAt': removedAt.toIso8601String(),
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {'peerId': 'peer-admin', 'role': 'admin'},
            ],
            'createdBy': 'peer-admin',
            'createdAt': initialGroupCreatedAt.toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': removedAt.toIso8601String(),
        });

        await delayedBridge.leaveStarted.future.timeout(
          const Duration(seconds: 2),
        );

        await groupRepo.updateGroup(
          testGroup.copyWith(
            myRole: GroupRole.member,
            lastMembershipEventAt: readdAt,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            joinedAt: initialMemberJoinedAt,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-self',
            username: 'Me',
            role: MemberRole.writer,
            publicKey: 'pk-self-current',
            joinedAt: readdAt,
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 2,
            encryptedKey: 'key-after-readd',
            createdAt: readdAt,
          ),
        );

        delayedBridge.completeLeave();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          delayedBridge.commandLog.where((command) => command == 'group:leave'),
          hasLength(1),
        );
        expect(delayedBridge.joinCalls, 1);
        expect(
          delayedBridge.commandLog.indexOf('group:join'),
          greaterThan(delayedBridge.commandLog.indexOf('group:leave')),
        );
        expect(removedGroups, isEmpty);

        final group = await groupRepo.getGroup('group-1');
        expect(group, isNotNull);
        expect(group!.lastMembershipEventAt, readdAt);
        final selfMember = await groupRepo.getMember('group-1', 'peer-self');
        expect(selfMember, isNotNull);
        expect(selfMember!.joinedAt, readdAt);
        expect(selfMember.publicKey, 'pk-self-current');
        final latestKey = await groupRepo.getLatestKey('group-1');
        expect(latestKey, isNotNull);
        expect(latestKey!.keyGeneration, 2);
        expect(latestKey.encryptedKey, 'key-after-readd');
        expect(
          (await msgRepo.getMessagesPage('group-1')).map((m) => m.text),
          contains('RA-011 retained old history'),
        );

        await sub.cancel();
        selfListener.dispose();
      },
    );

    test(
      'BB-010 self-removal leave failure preserves local state and emits no removed signal',
      () async {
        final selfJoinedAt = DateTime.utc(2026, 4, 5, 12);
        final removedAt = DateTime.utc(2026, 4, 5, 12, 0, 1);
        final eventLog = _FakeEventLog();
        bridge.responses['group:leave'] = {
          'ok': false,
          'errorCode': 'GROUP_ERROR',
          'errorMessage': 'forced leave failure',
        };
        final selfListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
          appendGroupEventLogEntry: eventLog.append,
        );

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-self',
            username: 'Me',
            role: MemberRole.writer,
            publicKey: 'pk-self',
            joinedAt: selfJoinedAt,
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 1,
            encryptedKey: 'key-bb010',
            createdAt: selfJoinedAt,
          ),
        );
        await groupRepo.updateGroup(
          testGroup.copyWith(myRole: GroupRole.member),
        );

        final removedGroups = <String>[];
        final sub = selfListener.groupRemovedStream.listen(removedGroups.add);
        final signedPayload = await signedAuditSystemPayload(
          transitionType: 'member_removed',
          sourceEventId: 'bb010-self-removal-1',
          eventAt: removedAt,
          systemPayload: {
            '__sys': 'member_removed',
            'member': {'peerId': 'peer-self', 'username': 'Me'},
            'removedAt': removedAt.toIso8601String(),
            'groupConfig': {
              'name': 'Test Group',
              'groupType': 'chat',
              'members': [
                {'peerId': 'peer-admin', 'role': 'admin'},
              ],
              'createdBy': 'peer-admin',
              'createdAt': initialGroupCreatedAt.toIso8601String(),
            },
          },
        );

        await expectLater(
          selfListener.handleReplayEnvelope({
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'messageId': 'bb010-self-removal-1',
            'text': jsonEncode(signedPayload),
            'timestamp': removedAt.toIso8601String(),
          }, rethrowOnError: true),
          throwsA(
            isA<BridgeCommandException>()
                .having((error) => error.command, 'command', 'group:leave')
                .having((error) => error.errorCode, 'errorCode', 'GROUP_ERROR'),
          ),
        );

        expect(
          bridge.commandLog.where((command) => command == 'group:leave'),
          hasLength(1),
        );
        expect(await groupRepo.getGroup('group-1'), isNotNull);
        expect(await groupRepo.getMember('group-1', 'peer-self'), isNotNull);
        expect(await groupRepo.getLatestKey('group-1'), isNotNull);
        expect(removedGroups, isEmpty);
        expect(eventLog.entries, isEmpty);
        expect(msgRepo.count, 0);

        await sub.cancel();
        selfListener.dispose();
      },
    );

    test(
      'GM-016 self-removal ignores stale post-leave envelopes without rejoining',
      () async {
        final selfJoinedAt = DateTime.utc(2026, 4, 5, 12);
        final removedAt = DateTime.utc(2026, 4, 5, 12, 0, 1);
        final staleSentAt = removedAt.add(const Duration(seconds: 5));
        final selfListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
        );

        await groupRepo.updateGroup(
          testGroup.copyWith(myRole: GroupRole.member),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-self',
            username: 'Me',
            role: MemberRole.writer,
            joinedAt: selfJoinedAt,
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 1,
            encryptedKey: 'gm016-key',
            createdAt: selfJoinedAt,
          ),
        );

        final removedGroups = <String>[];
        final emittedMessages = <GroupMessage>[];
        final removedSub = selfListener.groupRemovedStream.listen(
          removedGroups.add,
        );
        final messageSub = selfListener.groupMessageStream.listen(
          emittedMessages.add,
        );
        selfListener.start(sourceController.stream);

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 1,
          'text': jsonEncode({
            '__sys': 'member_removed',
            'member': {'peerId': 'peer-self', 'username': 'Me'},
            'removedAt': removedAt.toIso8601String(),
            'groupConfig': {
              'name': 'Test Group',
              'groupType': 'chat',
              'members': [
                {'peerId': 'peer-admin', 'role': 'admin'},
              ],
              'createdBy': 'peer-admin',
              'createdAt': initialGroupCreatedAt.toIso8601String(),
            },
          }),
          'timestamp': removedAt.toIso8601String(),
          'messageId': 'gm016-member-removed',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 1,
          'text': 'GM-016 stale post-leave message',
          'timestamp': staleSentAt.toIso8601String(),
          'messageId': 'gm016-stale-post-leave',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(
          bridge.commandLog.where((command) => command == 'group:leave'),
          hasLength(1),
        );
        expect(bridge.commandLog, isNot(contains('group:join')));
        expect(bridge.commandLog, isNot(contains('group:joinWithConfig')));
        expect(await groupRepo.getGroup('group-1'), isNull);
        expect(await groupRepo.getMembers('group-1'), isEmpty);
        expect(await groupRepo.getLatestKey('group-1'), isNull);
        expect(await msgRepo.getMessage('gm016-stale-post-leave'), isNull);
        expect(removedGroups, <String>['group-1']);
        expect(emittedMessages, isEmpty);

        await removedSub.cancel();
        await messageSub.cancel();
        selfListener.dispose();
      },
    );

    test(
      'duplicate self-removal emits one removal signal and leaves once',
      () async {
        final selfJoinedAt = DateTime.utc(2026, 4, 5, 12);
        final removedAt = DateTime.utc(2026, 4, 5, 12, 0, 1);
        final selfListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
        );

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-self',
            username: 'Me',
            role: MemberRole.writer,
            joinedAt: selfJoinedAt,
          ),
        );
        await groupRepo.updateGroup(
          testGroup.copyWith(myRole: GroupRole.member),
        );

        selfListener.start(sourceController.stream);

        final removedGroups = <String>[];
        final sub = selfListener.groupRemovedStream.listen(removedGroups.add);

        final sysText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-self', 'username': 'Me'},
          'removedAt': removedAt.toIso8601String(),
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {'peerId': 'peer-admin', 'role': 'admin'},
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        final duplicateEvent = {
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': removedAt.toIso8601String(),
        };

        sourceController.add(duplicateEvent);
        sourceController.add(duplicateEvent);

        await Future.delayed(const Duration(milliseconds: 50));

        expect(
          bridge.commandLog.where((command) => command == 'group:leave'),
          hasLength(1),
        );
        expect(removedGroups, ['group-1']);
        expect(await groupRepo.getGroup('group-1'), isNull);
        expect(msgRepo.count, 0);

        await sub.cancel();
        selfListener.dispose();
      },
    );

    test(
      'LP003 member_removed self-removal is the ban-equivalent leave path',
      () async {
        final selfJoinedAt = DateTime.utc(2026, 4, 5, 12);
        final removedAt = DateTime.utc(2026, 4, 5, 12, 0, 1);
        final selfListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
        );

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-self',
            username: 'Me',
            role: MemberRole.writer,
            joinedAt: selfJoinedAt,
          ),
        );
        await groupRepo.updateGroup(
          testGroup.copyWith(myRole: GroupRole.member),
        );

        final removedGroups = <String>[];
        final sub = selfListener.groupRemovedStream.listen(removedGroups.add);

        await selfListener.handleReplayEnvelope({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': jsonEncode({
            '__sys': 'member_removed',
            'member': {'peerId': 'peer-self', 'username': 'Me'},
            'removedAt': removedAt.toIso8601String(),
            'groupConfig': {
              'name': 'Test Group',
              'groupType': 'chat',
              'members': [
                {'peerId': 'peer-admin', 'role': 'admin'},
              ],
              'createdBy': 'peer-admin',
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            },
          }),
          'timestamp': removedAt.toIso8601String(),
        });

        expect(
          bridge.commandLog.where((command) => command == 'group:leave'),
          hasLength(1),
        );
        expect(await groupRepo.getGroup('group-1'), isNull);
        expect(removedGroups, ['group-1']);

        await sub.cancel();
        selfListener.dispose();
      },
    );

    test(
      'older member_added cannot revive state after a newer removal across restart',
      () async {
        final newerListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        newerListener.start(sourceController.stream);

        const newerRemoveAt = '2026-04-05T12:00:02.000Z';
        final newerRemove = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-sender', 'username': 'Sender'},
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': newerRemove,
          'timestamp': newerRemoveAt,
        });

        await Future.delayed(const Duration(milliseconds: 50));
        newerListener.dispose();

        final persistedAfterRemove = await groupRepo.getGroup('group-1');
        expect(
          persistedAfterRemove!.lastMembershipEventAt,
          DateTime.parse(newerRemoveAt).toUtc(),
        );
        expect(await groupRepo.getMember('group-1', 'peer-sender'), isNull);

        final restartedListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        restartedListener.start(sourceController.stream);

        final olderAdd = jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': 'peer-sender',
            'username': 'Sender',
            'role': 'writer',
            'publicKey': 'pk-sender',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': olderAdd,
          'timestamp': '2026-04-05T12:00:01.000Z',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(await groupRepo.getMember('group-1', 'peer-sender'), isNull);
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(1),
        );

        restartedListener.dispose();
      },
    );

    test(
      'GM-029 older versioned config snapshots are ignored after newer version and same-version replay is idempotent',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-charlie',
            username: 'Charlie',
            role: MemberRole.reader,
            publicKey: 'pk-charlie',
            joinedAt: initialMemberJoinedAt,
          ),
        );

        Map<String, dynamic> memberEntry({
          required String peerId,
          required String username,
          required String role,
          String? publicKey,
          Map<String, dynamic>? permissions,
        }) {
          return {
            'peerId': peerId,
            'username': username,
            'role': role,
            'publicKey': publicKey ?? 'pk-$peerId',
            'permissions': ?permissions,
          };
        }

        Map<String, dynamic> versionedConfig({
          required DateTime version,
          required List<Map<String, dynamic>> members,
        }) {
          final payload = <String, dynamic>{
            'name': 'Test Group',
            'groupType': 'chat',
            'members': members,
            'createdBy': 'peer-admin',
            'createdAt': initialGroupCreatedAt.toIso8601String(),
            groupConfigVersionField: version.toUtc().toIso8601String(),
          };
          return {
            ...payload,
            groupConfigStateHashField: buildGroupConfigStateHash(
              groupId: 'group-1',
              groupConfig: payload,
            ),
          };
        }

        final version2 = DateTime.utc(2026, 4, 5, 12, 0, 2);
        final version4 = DateTime.utc(2026, 4, 5, 12, 0, 4);
        final admin = memberEntry(
          peerId: 'peer-admin',
          username: 'Admin',
          role: 'admin',
          publicKey: 'pk-admin',
        );
        final sender = memberEntry(
          peerId: 'peer-sender',
          username: 'Sender',
          role: 'writer',
          publicKey: 'pk-sender',
        );
        final charlieWriter = memberEntry(
          peerId: 'peer-charlie',
          username: 'Charlie',
          role: 'writer',
          publicKey: 'pk-charlie',
          permissions: {'deleteMessages': true},
        );
        final latestConfig = versionedConfig(
          version: version4,
          members: [admin, sender, charlieWriter],
        );
        final staleRemovedConfig = versionedConfig(
          version: version2,
          members: [admin, sender],
        );
        final latestRoleUpdate = {
          '__sys': 'member_role_updated',
          'member': charlieWriter,
          'groupConfig': latestConfig,
        };
        final staleRemoval = {
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-charlie', 'username': 'Charlie'},
          'removedAt': version2.toIso8601String(),
          'groupConfig': staleRemovedConfig,
        };

        listener.start(sourceController.stream);
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': jsonEncode(latestRoleUpdate),
          'timestamp': version4
              .add(const Duration(minutes: 1))
              .toIso8601String(),
          'messageId': 'gm029-latest-role',
        });
        await Future.delayed(const Duration(milliseconds: 50));

        final afterLatest = await groupRepo.getMember(
          'group-1',
          'peer-charlie',
        );
        expect(afterLatest, isNotNull);
        expect(afterLatest!.role, MemberRole.writer);
        expect(afterLatest.permissions.deleteMessages, isTrue);
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(1),
        );

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': jsonEncode(latestRoleUpdate),
          'timestamp': version4
              .add(const Duration(minutes: 1))
              .toIso8601String(),
          'messageId': 'gm029-latest-role-duplicate',
        });
        await Future.delayed(const Duration(milliseconds: 50));
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(1),
        );

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': jsonEncode(staleRemoval),
          'timestamp': version4
              .add(const Duration(minutes: 2))
              .toIso8601String(),
          'messageId': 'gm029-stale-remove',
        });
        await Future.delayed(const Duration(milliseconds: 50));

        final persisted = await groupRepo.getMember('group-1', 'peer-charlie');
        expect(persisted, isNotNull);
        expect(persisted!.role, MemberRole.writer);
        expect(persisted.permissions.deleteMessages, isTrue);
        expect(
          (await groupRepo.getGroup('group-1'))!.lastMembershipEventAt,
          version4,
        );
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(1),
        );
      },
    );

    test(
      'GM-011 stale member_added delivered after newer remove keeps Charlie removed',
      () async {
        await groupRepo.removeMember('group-1', 'peer-sender');
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob',
            joinedAt: DateTime.parse('2026-04-05T12:00:00.000Z'),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-charlie',
            joinedAt: DateTime.parse('2026-04-05T12:00:01.000Z'),
          ),
        );

        final addV2At = DateTime.parse('2026-04-05T12:00:02.000Z');
        final removeV3At = DateTime.parse('2026-04-05T12:00:03.000Z');
        final staleAddText = jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': 'peer-charlie',
            'username': 'Charlie',
            'role': 'writer',
            'publicKey': 'pk-charlie',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {'peerId': 'peer-bob', 'role': 'writer', 'publicKey': 'pk-bob'},
              {
                'peerId': 'peer-charlie',
                'role': 'writer',
                'publicKey': 'pk-charlie',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        final newerRemoveText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-charlie', 'username': 'Charlie'},
          'removedAt': removeV3At.toUtc().toIso8601String(),
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {'peerId': 'peer-bob', 'role': 'writer', 'publicKey': 'pk-bob'},
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        final newerListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        newerListener.start(sourceController.stream);
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': newerRemoveText,
          'timestamp': removeV3At.toUtc().toIso8601String(),
        });
        await Future.delayed(const Duration(milliseconds: 50));
        newerListener.dispose();

        expect(await groupRepo.getMember('group-1', 'peer-charlie'), isNull);
        expect(
          (await groupRepo.getGroup('group-1'))!.lastMembershipEventAt,
          removeV3At.toUtc(),
        );

        final updateAfterRemove =
            jsonDecode(
                  bridge.sentMessages.where((message) {
                    final parsed = jsonDecode(message) as Map<String, dynamic>;
                    return parsed['cmd'] == 'group:updateConfig';
                  }).single,
                )
                as Map<String, dynamic>;
        final removeConfig =
            updateAfterRemove['payload']['groupConfig'] as Map<String, dynamic>;
        expect(
          (removeConfig['members'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((member) => member['peerId']),
          isNot(contains('peer-charlie')),
        );

        final restartedListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        restartedListener.start(sourceController.stream);
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': staleAddText,
          'timestamp': addV2At.toUtc().toIso8601String(),
        });
        await Future.delayed(const Duration(milliseconds: 50));

        expect(await groupRepo.getMember('group-1', 'peer-charlie'), isNull);
        expect(
          (await groupRepo.getGroup('group-1'))!.lastMembershipEventAt,
          removeV3At.toUtc(),
        );
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(1),
        );
        expect(
          (await msgRepo.getMessagesPage(
            'group-1',
          )).map((message) => message.text),
          isNot(contains('Admin added Charlie')),
        );

        restartedListener.dispose();
      },
    );

    test(
      'GM-012 stale member_removed delivered after newer re-add keeps Charlie current after restart',
      () async {
        await groupRepo.removeMember('group-1', 'peer-sender');

        Map<String, dynamic> memberConfig({
          required String peerId,
          required String username,
          required String role,
          required String publicKey,
          List<Map<String, dynamic>> devices = const <Map<String, dynamic>>[],
        }) {
          return {
            'peerId': peerId,
            'username': username,
            'role': role,
            'publicKey': publicKey,
            if (devices.isNotEmpty) 'devices': devices,
          };
        }

        Map<String, dynamic> deviceConfig(String deviceId) {
          return {
            'deviceId': deviceId,
            'transportPeerId': deviceId,
            'deviceSigningPublicKey': 'pk-$deviceId',
            'mlKemPublicKey': 'mlkem-$deviceId',
            'keyPackageId': 'key-package-$deviceId',
            'keyPackagePublicMaterial': 'key-package-public-$deviceId',
          };
        }

        List<Map<String, dynamic>> updateConfigPayloads() {
          return bridge.sentMessages
              .map((message) => jsonDecode(message) as Map<String, dynamic>)
              .where((message) => message['cmd'] == 'group:updateConfig')
              .map(
                (message) => Map<String, dynamic>.from(
                  (message['payload'] as Map<String, dynamic>)['groupConfig']
                      as Map,
                ),
              )
              .toList(growable: false);
        }

        final bobMember = GroupMember(
          groupId: 'group-1',
          peerId: 'peer-bob',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-bob',
          joinedAt: DateTime.parse('2026-04-05T12:00:00.000Z'),
        );
        final initialCharlieMember = GroupMember(
          groupId: 'group-1',
          peerId: 'peer-charlie',
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-charlie-v1',
          devices: [
            GroupMemberDeviceIdentity(
              deviceId: 'device-charlie-v1',
              transportPeerId: 'device-charlie-v1',
              deviceSigningPublicKey: 'pk-device-charlie-v1',
              mlKemPublicKey: 'mlkem-device-charlie-v1',
              keyPackageId: 'key-package-device-charlie-v1',
              keyPackagePublicMaterial: 'key-package-public-device-charlie-v1',
            ),
          ],
          joinedAt: DateTime.parse('2026-04-05T12:00:01.000Z'),
        );
        await groupRepo.saveMember(bobMember);
        await groupRepo.saveMember(initialCharlieMember);

        final removeV2At = DateTime.parse('2026-04-05T12:00:02.000Z');
        final readdV3At = DateTime.parse('2026-04-05T12:00:03.000Z');
        final adminConfig = memberConfig(
          peerId: 'peer-admin',
          username: 'Admin',
          role: 'admin',
          publicKey: 'pk-admin',
        );
        final bobConfig = memberConfig(
          peerId: 'peer-bob',
          username: 'Bob',
          role: 'writer',
          publicKey: 'pk-bob',
        );
        final charlieV3Config = memberConfig(
          peerId: 'peer-charlie',
          username: 'Charlie',
          role: 'writer',
          publicKey: 'pk-charlie-v3',
          devices: [deviceConfig('device-charlie-v3')],
        );
        final staleRemoveText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-charlie', 'username': 'Charlie'},
          'removedAt': removeV2At.toUtc().toIso8601String(),
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [adminConfig, bobConfig],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });
        final readdText = jsonEncode({
          '__sys': 'member_added',
          'member': charlieV3Config,
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [adminConfig, bobConfig, charlieV3Config],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        final removeListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        removeListener.start(sourceController.stream);
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': staleRemoveText,
          'timestamp': removeV2At.toUtc().toIso8601String(),
        });
        await Future.delayed(const Duration(milliseconds: 50));
        removeListener.dispose();

        expect(await groupRepo.getMember('group-1', 'peer-charlie'), isNull);
        expect(
          (await groupRepo.getGroup('group-1'))!.lastMembershipEventAt,
          removeV2At.toUtc(),
        );
        expect(updateConfigPayloads(), hasLength(1));
        expect(
          (updateConfigPayloads().single['members'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((member) => member['peerId']),
          isNot(contains('peer-charlie')),
        );

        final readdListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        readdListener.start(sourceController.stream);
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': readdText,
          'timestamp': readdV3At.toUtc().toIso8601String(),
        });
        await Future.delayed(const Duration(milliseconds: 50));
        readdListener.dispose();

        final charlieAfterReadd = await groupRepo.getMember(
          'group-1',
          'peer-charlie',
        );
        expect(charlieAfterReadd, isNotNull);
        expect(charlieAfterReadd!.publicKey, 'pk-charlie-v3');
        expect(charlieAfterReadd.joinedAt, readdV3At.toUtc());
        expect(charlieAfterReadd.activeDevices, hasLength(1));
        expect(
          charlieAfterReadd.activeDevices.single.deviceId,
          'device-charlie-v3',
        );
        expect(
          (await groupRepo.getGroup('group-1'))!.lastMembershipEventAt,
          readdV3At.toUtc(),
        );
        expect(updateConfigPayloads(), hasLength(2));
        expect(
          (updateConfigPayloads().last['members'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((member) => member['peerId']),
          contains('peer-charlie'),
        );

        final updateConfigCountAfterReadd = bridge.commandLog
            .where((command) => command == 'group:updateConfig')
            .length;
        final restartedListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        restartedListener.start(sourceController.stream);
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': staleRemoveText,
          'timestamp': removeV2At.toUtc().toIso8601String(),
        });
        await Future.delayed(const Duration(milliseconds: 50));

        final charlieAfterStaleRemove = await groupRepo.getMember(
          'group-1',
          'peer-charlie',
        );
        expect(charlieAfterStaleRemove, isNotNull);
        expect(charlieAfterStaleRemove!.publicKey, 'pk-charlie-v3');
        expect(charlieAfterStaleRemove.joinedAt, readdV3At.toUtc());
        expect(charlieAfterStaleRemove.activeDevices, hasLength(1));
        expect(
          charlieAfterStaleRemove.activeDevices.single.deviceId,
          'device-charlie-v3',
        );
        expect(
          (await groupRepo.getGroup('group-1'))!.lastMembershipEventAt,
          readdV3At.toUtc(),
        );
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(updateConfigCountAfterReadd),
        );
        final timelineTexts = (await msgRepo.getMessagesPage(
          'group-1',
        )).map((message) => message.text).toList();
        expect(
          timelineTexts.where((text) => text == 'Admin removed Charlie'),
          hasLength(1),
        );
        expect(
          timelineTexts.where((text) => text == 'Admin added Charlie'),
          hasLength(1),
        );

        restartedListener.dispose();
      },
    );

    test(
      'KE-012 delayed old config after re-add cannot remove active members',
      () async {
        listener.start(sourceController.stream);

        final staleConfigAt = DateTime.parse('2026-04-05T12:00:01.000Z');
        final bobJoinedAt = DateTime.parse('2026-04-05T12:00:02.000Z');
        final readdAt = DateTime.parse('2026-04-05T12:00:04.000Z');

        await groupRepo.updateGroup(
          testGroup.copyWith(lastMembershipEventAt: readdAt),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob',
            joinedAt: bobJoinedAt,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-charlie',
            joinedAt: readdAt,
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 2,
            encryptedKey: 'readd-key',
            createdAt: readdAt,
          ),
        );

        final staleConfigPayload = jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': 'peer-bob',
            'username': 'Bob',
            'role': 'writer',
            'publicKey': 'pk-bob',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': staleConfigPayload,
          'timestamp': staleConfigAt.toUtc().toIso8601String(),
        });
        await Future.delayed(const Duration(milliseconds: 50));

        final members = await groupRepo.getMembers('group-1');
        expect(
          members.map((member) => member.peerId).toSet(),
          containsAll(<String>{'peer-admin', 'peer-bob', 'peer-charlie'}),
        );
        expect(
          (await groupRepo.getMember('group-1', 'peer-bob'))!.joinedAt,
          bobJoinedAt.toUtc(),
        );
        expect(
          (await groupRepo.getMember('group-1', 'peer-charlie'))!.joinedAt,
          readdAt.toUtc(),
        );
        expect(
          (await groupRepo.getGroup('group-1'))!.lastMembershipEventAt,
          readdAt.toUtc(),
        );
        expect((await groupRepo.getLatestKey('group-1'))!.keyGeneration, 2);
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          isEmpty,
        );
      },
    );

    test(
      'ML-012 concurrent remove C and add D merge regardless delivery order',
      () async {
        listener.start(sourceController.stream);

        Map<String, dynamic> memberConfig(
          String peerId,
          String username,
          MemberRole role, {
          DateTime? joinedAt,
        }) {
          return {
            'peerId': peerId,
            'username': username,
            'role': role.toValue(),
            'joinedAt': (joinedAt ?? initialMemberJoinedAt)
                .toUtc()
                .toIso8601String(),
            'publicKey': 'pk-$peerId',
          };
        }

        Future<void> seedGroup(String groupId) async {
          await groupRepo.saveGroup(
            testGroup.copyWith(id: groupId, topicName: 'topic-$groupId'),
          );
          await groupRepo.saveMember(
            GroupMember(
              groupId: groupId,
              peerId: 'peer-admin',
              username: 'Admin',
              role: MemberRole.admin,
              publicKey: 'pk-peer-admin',
              joinedAt: initialMemberJoinedAt,
            ),
          );
          await groupRepo.saveMember(
            GroupMember(
              groupId: groupId,
              peerId: 'peer-sender',
              username: 'Sender',
              role: MemberRole.admin,
              publicKey: 'pk-peer-sender',
              joinedAt: initialMemberJoinedAt,
            ),
          );
          await groupRepo.saveMember(
            GroupMember(
              groupId: groupId,
              peerId: 'peer-charlie',
              username: 'Charlie',
              role: MemberRole.writer,
              publicKey: 'pk-peer-charlie',
              joinedAt: initialMemberJoinedAt,
            ),
          );
        }

        Map<String, dynamic> groupConfig(
          String groupId,
          List<Map<String, dynamic>> members,
        ) {
          return {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': members,
            'createdBy': 'peer-admin',
            'createdAt': initialGroupCreatedAt.toUtc().toIso8601String(),
          };
        }

        Map<String, dynamic> envelope({
          required String groupId,
          required String senderId,
          required String senderUsername,
          required DateTime timestamp,
          required Map<String, dynamic> payload,
        }) {
          return {
            'groupId': groupId,
            'senderId': senderId,
            'senderUsername': senderUsername,
            'keyEpoch': 0,
            'text': jsonEncode(payload),
            'timestamp': timestamp.toUtc().toIso8601String(),
          };
        }

        Set<String> latestSyncedMembers(String groupId) {
          for (final raw in bridge.sentMessages.reversed) {
            final decoded = jsonDecode(raw) as Map<String, dynamic>;
            if (decoded['cmd'] != 'group:updateConfig') {
              continue;
            }
            final payload = decoded['payload'] as Map<String, dynamic>;
            if (payload['groupId'] != groupId) {
              continue;
            }
            final config = payload['groupConfig'] as Map<String, dynamic>;
            final members = config['members'] as List<dynamic>;
            return members
                .whereType<Map<String, dynamic>>()
                .map((member) => member['peerId'] as String)
                .toSet();
          }
          return const <String>{};
        }

        Future<void> runOrder({
          required String groupId,
          required bool removeFirst,
        }) async {
          await seedGroup(groupId);
          final addAt = DateTime.parse('2026-04-05T12:40:01.000Z');
          final removeAt = DateTime.parse('2026-04-05T12:40:02.000Z');
          final admin = memberConfig('peer-admin', 'Admin', MemberRole.admin);
          final sender = memberConfig(
            'peer-sender',
            'Sender',
            MemberRole.admin,
          );
          final charlie = memberConfig(
            'peer-charlie',
            'Charlie',
            MemberRole.writer,
          );
          final diana = memberConfig(
            'peer-diana',
            'Diana',
            MemberRole.writer,
            joinedAt: addAt,
          );
          final addD = envelope(
            groupId: groupId,
            senderId: 'peer-sender',
            senderUsername: 'Sender',
            timestamp: addAt,
            payload: {
              '__sys': 'member_added',
              'member': diana,
              'groupConfig': groupConfig(groupId, [
                admin,
                sender,
                charlie,
                diana,
              ]),
            },
          );
          final removeC = envelope(
            groupId: groupId,
            senderId: 'peer-admin',
            senderUsername: 'Admin',
            timestamp: removeAt,
            payload: {
              '__sys': 'member_removed',
              'member': {'peerId': 'peer-charlie', 'username': 'Charlie'},
              'removedAt': removeAt.toUtc().toIso8601String(),
              'groupConfig': groupConfig(groupId, [admin, sender]),
            },
          );

          for (final event in removeFirst ? [removeC, addD] : [addD, removeC]) {
            sourceController.add(event);
            await Future.delayed(const Duration(milliseconds: 50));
          }

          final members = await groupRepo.getMembers(groupId);
          expect(
            {for (final member in members) member.peerId: member.role},
            {
              'peer-admin': MemberRole.admin,
              'peer-sender': MemberRole.admin,
              'peer-diana': MemberRole.writer,
            },
          );
          expect(await groupRepo.getMember(groupId, 'peer-charlie'), isNull);
          expect(
            (await groupRepo.getGroup(groupId))!.lastMembershipEventAt,
            removeAt.toUtc(),
          );
          expect(latestSyncedMembers(groupId), {
            'peer-admin',
            'peer-sender',
            'peer-diana',
          });
        }

        await runOrder(groupId: 'group-ml012-add-first', removeFirst: false);
        await runOrder(groupId: 'group-ml012-remove-first', removeFirst: true);
      },
    );

    test(
      'ML-012 remove and re-add same member use deterministic timestamp order',
      () async {
        listener.start(sourceController.stream);

        Future<void> seedGroup(String groupId) async {
          await groupRepo.saveGroup(
            testGroup.copyWith(id: groupId, topicName: 'topic-$groupId'),
          );
          for (final member in [
            GroupMember(
              groupId: groupId,
              peerId: 'peer-admin',
              username: 'Admin',
              role: MemberRole.admin,
              publicKey: 'pk-peer-admin',
              joinedAt: initialMemberJoinedAt,
            ),
            GroupMember(
              groupId: groupId,
              peerId: 'peer-sender',
              username: 'Sender',
              role: MemberRole.admin,
              publicKey: 'pk-peer-sender',
              joinedAt: initialMemberJoinedAt,
            ),
            GroupMember(
              groupId: groupId,
              peerId: 'peer-charlie',
              username: 'Charlie',
              role: MemberRole.writer,
              publicKey: 'pk-peer-charlie',
              joinedAt: initialMemberJoinedAt,
            ),
          ]) {
            await groupRepo.saveMember(member);
          }
        }

        Map<String, dynamic> memberConfig({required DateTime joinedAt}) {
          return {
            'peerId': 'peer-charlie',
            'username': 'Charlie',
            'role': 'writer',
            'joinedAt': joinedAt.toUtc().toIso8601String(),
            'publicKey': 'pk-peer-charlie',
          };
        }

        Map<String, dynamic> groupConfig(List<Map<String, dynamic>> members) {
          return {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': members,
            'createdBy': 'peer-admin',
            'createdAt': initialGroupCreatedAt.toUtc().toIso8601String(),
          };
        }

        Map<String, dynamic> baseAdmin() => {
          'peerId': 'peer-admin',
          'username': 'Admin',
          'role': 'admin',
          'joinedAt': initialMemberJoinedAt.toUtc().toIso8601String(),
          'publicKey': 'pk-peer-admin',
        };

        Map<String, dynamic> baseSender() => {
          'peerId': 'peer-sender',
          'username': 'Sender',
          'role': 'admin',
          'joinedAt': initialMemberJoinedAt.toUtc().toIso8601String(),
          'publicKey': 'pk-peer-sender',
        };

        Map<String, dynamic> envelope({
          required String groupId,
          required String senderId,
          required String senderUsername,
          required DateTime timestamp,
          required Map<String, dynamic> payload,
        }) {
          return {
            'groupId': groupId,
            'senderId': senderId,
            'senderUsername': senderUsername,
            'keyEpoch': 0,
            'text': jsonEncode(payload),
            'timestamp': timestamp.toUtc().toIso8601String(),
          };
        }

        Future<void> runConflict({
          required String groupId,
          required DateTime removeAt,
          required DateTime readdAt,
          required bool removeFirst,
          required bool expectCharlieActive,
        }) async {
          await seedGroup(groupId);
          final removeC = envelope(
            groupId: groupId,
            senderId: 'peer-admin',
            senderUsername: 'Admin',
            timestamp: removeAt,
            payload: {
              '__sys': 'member_removed',
              'member': {'peerId': 'peer-charlie', 'username': 'Charlie'},
              'removedAt': removeAt.toUtc().toIso8601String(),
              'groupConfig': groupConfig([baseAdmin(), baseSender()]),
            },
          );
          final readdC = envelope(
            groupId: groupId,
            senderId: 'peer-sender',
            senderUsername: 'Sender',
            timestamp: readdAt,
            payload: {
              '__sys': 'member_added',
              'member': memberConfig(joinedAt: readdAt),
              'groupConfig': groupConfig([
                baseAdmin(),
                baseSender(),
                memberConfig(joinedAt: readdAt),
              ]),
            },
          );

          for (final event
              in removeFirst ? [removeC, readdC] : [readdC, removeC]) {
            sourceController.add(event);
            await Future.delayed(const Duration(milliseconds: 50));
          }

          final charlie = await groupRepo.getMember(groupId, 'peer-charlie');
          if (expectCharlieActive) {
            expect(charlie, isNotNull);
            expect(charlie!.joinedAt, readdAt.toUtc());
          } else {
            expect(charlie, isNull);
          }
        }

        await runConflict(
          groupId: 'group-ml012-readd-wins-add-first',
          removeAt: DateTime.parse('2026-04-05T12:45:01.000Z'),
          readdAt: DateTime.parse('2026-04-05T12:45:02.000Z'),
          removeFirst: false,
          expectCharlieActive: true,
        );
        await runConflict(
          groupId: 'group-ml012-readd-wins-remove-first',
          removeAt: DateTime.parse('2026-04-05T12:46:01.000Z'),
          readdAt: DateTime.parse('2026-04-05T12:46:02.000Z'),
          removeFirst: true,
          expectCharlieActive: true,
        );
        await runConflict(
          groupId: 'group-ml012-remove-wins-tie-add-first',
          removeAt: DateTime.parse('2026-04-05T12:47:01.000Z'),
          readdAt: DateTime.parse('2026-04-05T12:47:01.000Z'),
          removeFirst: false,
          expectCharlieActive: false,
        );
        await runConflict(
          groupId: 'group-ml012-remove-wins-tie-remove-first',
          removeAt: DateTime.parse('2026-04-05T12:48:01.000Z'),
          readdAt: DateTime.parse('2026-04-05T12:48:01.000Z'),
          removeFirst: true,
          expectCharlieActive: false,
        );
      },
    );

    test(
      'ML-009 delayed older member_removed cannot roll back a rapid re-add',
      () async {
        listener.start(sourceController.stream);

        final initialCharlieAt = DateTime.parse('2026-04-05T12:00:00.000Z');
        final removeAt = DateTime.parse('2026-04-05T12:00:01.000Z');
        final readdAt = DateTime.parse('2026-04-05T12:00:02.000Z');

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-charlie',
            joinedAt: initialCharlieAt,
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 2,
            encryptedKey: 'readd-key',
            createdAt: readdAt,
          ),
        );

        final removePayload = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-charlie', 'username': 'Charlie'},
          'removedAt': removeAt.toUtc().toIso8601String(),
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        final addPayload = jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': 'peer-charlie',
            'username': 'Charlie',
            'role': 'writer',
            'publicKey': 'pk-charlie',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
              {
                'peerId': 'peer-charlie',
                'username': 'Charlie',
                'role': 'writer',
                'publicKey': 'pk-charlie',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': addPayload,
          'timestamp': readdAt.toUtc().toIso8601String(),
        });
        await Future.delayed(const Duration(milliseconds: 50));

        final charlieAfterReadd = await groupRepo.getMember(
          'group-1',
          'peer-charlie',
        );
        expect(charlieAfterReadd, isNotNull);
        expect(charlieAfterReadd!.joinedAt, readdAt.toUtc());
        expect(
          (await groupRepo.getGroup('group-1'))!.lastMembershipEventAt,
          readdAt.toUtc(),
        );

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': removePayload,
          'timestamp': removeAt.toUtc().toIso8601String(),
        });
        await Future.delayed(const Duration(milliseconds: 50));

        final charlieAfterDelayedRemove = await groupRepo.getMember(
          'group-1',
          'peer-charlie',
        );
        expect(charlieAfterDelayedRemove, isNotNull);
        expect(charlieAfterDelayedRemove!.joinedAt, readdAt.toUtc());
        expect(
          (await groupRepo.getGroup('group-1'))!.lastMembershipEventAt,
          readdAt.toUtc(),
        );
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(1),
        );
      },
    );

    test('handles key_rotated system message without error', () async {
      listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
      );
      listener.start(sourceController.stream);

      final sysText = jsonEncode({'__sys': 'key_rotated', 'newKeyEpoch': 2});

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      // System message should NOT be saved as a regular message
      expect(msgRepo.count, 0);

      // No crash, no error — just handled gracefully
    });

    test('removal of other member does NOT call leaveGroup', () async {
      // Create a listener that knows its own peerId
      final selfListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
      );
      selfListener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'member_removed',
        'member': {'peerId': 'peer-sender', 'username': 'Sender'},
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-admin', 'role': 'admin'},
            {'peerId': 'peer-self', 'role': 'writer'},
          ],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      // Bridge should NOT have received group:leave
      expect(bridge.commandLog, isNot(contains('group:leave')));

      // Bridge should have received group:updateConfig
      expect(bridge.commandLog, contains('group:updateConfig'));

      // Group should still exist
      final group = await groupRepo.getGroup('group-1');
      expect(group, isNotNull);

      selfListener.dispose();
    });

    test('member_role_updated changes role and calls updateConfig', () async {
      listener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'member_role_updated',
        'member': {
          'peerId': 'peer-sender',
          'username': 'Sender',
          'role': 'admin',
          'publicKey': 'pk-sender',
        },
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-admin', 'role': 'admin', 'publicKey': 'pk-admin'},
            {
              'peerId': 'peer-sender',
              'role': 'admin',
              'publicKey': 'pk-sender',
            },
          ],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      final updated = await groupRepo.getMember('group-1', 'peer-sender');
      expect(updated, isNotNull);
      expect(updated!.role, MemberRole.admin);
      expect(bridge.commandLog, contains('group:updateConfig'));
      expect(msgRepo.count, 1);
      final saved = await msgRepo.getLatestMessage('group-1');
      expect(saved, isNotNull);
      expect(saved!.text, 'Admin made Sender an admin');
      expect(
        saved.id.startsWith('sys-member_role_updated:group-1:peer-sender:'),
        isTrue,
      );
    });

    test(
      'member_role_updated logs event and rejects tampered replay before mutation',
      () async {
        final eventLog = _FakeEventLog();
        listener.dispose();
        listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          appendGroupEventLogEntry: eventLog.append,
        );
        listener.start(sourceController.stream);

        Map<String, dynamic> rolePayload(String role) => {
          '__sys': 'member_role_updated',
          'member': {
            'peerId': 'peer-sender',
            'username': 'Sender',
            'role': role,
            'publicKey': 'pk-sender',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {'peerId': 'peer-sender', 'role': role, 'publicKey': 'pk-sender'},
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.utc(2026, 4, 30).toIso8601String(),
          },
        };

        final roleEventAt = DateTime.utc(2026, 4, 30, 12);
        final signedRolePayload = await signedAuditSystemPayload(
          transitionType: 'member_role_updated',
          sourceEventId: 'role-event-1',
          eventAt: roleEventAt,
          systemPayload: rolePayload('admin'),
        );

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'messageId': 'role-event-1',
          'text': jsonEncode(signedRolePayload),
          'timestamp': roleEventAt.toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(eventLog.entries, hasLength(1));
        expect(eventLog.entries.single['eventType'], 'member_role_updated');
        expect(eventLog.entries.single['sourceEventId'], 'role-event-1');
        expect(
          (await groupRepo.getMember('group-1', 'peer-sender'))!.role,
          MemberRole.admin,
        );

        final tamperedRolePayload = {
          ...rolePayload('member'),
          signedGroupTransitionAuditField:
              signedRolePayload[signedGroupTransitionAuditField],
        };
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'messageId': 'role-event-1',
          'text': jsonEncode(tamperedRolePayload),
          'timestamp': roleEventAt.toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(eventLog.entries, hasLength(1));
        expect(
          (await groupRepo.getMember('group-1', 'peer-sender'))!.role,
          MemberRole.admin,
        );
      },
    );

    test('unauthorized member_role_updated is ignored', () async {
      listener.start(sourceController.stream);

      final sysText = jsonEncode({
        '__sys': 'member_role_updated',
        'member': {
          'peerId': 'peer-admin',
          'username': 'Admin',
          'role': 'writer',
          'publicKey': 'pk-admin',
        },
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-admin', 'role': 'writer', 'publicKey': 'pk-admin'},
            {
              'peerId': 'peer-sender',
              'role': 'writer',
              'publicKey': 'pk-sender',
            },
          ],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(await groupRepo.getMember('group-1', 'peer-sender'), isNotNull);
      expect(await groupRepo.getGroup('group-1'), isNotNull);
      expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      expect(msgRepo.count, 0);
    });

    test(
      'limited manager member_role_updated cannot promote a member to admin',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-manager',
            username: 'Manager',
            role: MemberRole.writer,
            permissions: const GroupMemberPermissions(manageRoles: true),
            publicKey: 'pk-manager',
            joinedAt: initialMemberJoinedAt,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-target',
            username: 'Target',
            role: MemberRole.reader,
            publicKey: 'pk-target',
            joinedAt: initialMemberJoinedAt,
          ),
        );

        listener.start(sourceController.stream);

        final sysText = jsonEncode({
          '__sys': 'member_role_updated',
          'member': {
            'peerId': 'peer-target',
            'username': 'Target',
            'role': 'admin',
            'publicKey': 'pk-target',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-manager',
                'role': 'writer',
                'permissions': {'manageRoles': true},
                'publicKey': 'pk-manager',
              },
              {
                'peerId': 'peer-target',
                'role': 'admin',
                'publicKey': 'pk-target',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-manager',
          'senderUsername': 'Manager',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final target = await groupRepo.getMember('group-1', 'peer-target');
        expect(target, isNotNull);
        expect(target!.role, MemberRole.reader);
        expect(bridge.commandLog, isNot(contains('group:updateConfig')));
        expect(msgRepo.count, 0);
      },
    );

    test(
      'limited manager member_role_updated cannot demote an admin',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-manager',
            username: 'Manager',
            role: MemberRole.writer,
            permissions: const GroupMemberPermissions(manageRoles: true),
            publicKey: 'pk-manager',
            joinedAt: initialMemberJoinedAt,
          ),
        );

        listener.start(sourceController.stream);

        final sysText = jsonEncode({
          '__sys': 'member_role_updated',
          'member': {
            'peerId': 'peer-admin',
            'username': 'Admin',
            'role': 'writer',
            'publicKey': 'pk-admin',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-manager',
                'role': 'writer',
                'permissions': {'manageRoles': true},
                'publicKey': 'pk-manager',
              },
              {
                'peerId': 'peer-admin',
                'role': 'writer',
                'publicKey': 'pk-admin',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-manager',
          'senderUsername': 'Manager',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final admin = await groupRepo.getMember('group-1', 'peer-admin');
        expect(admin, isNotNull);
        expect(admin!.role, MemberRole.admin);
        expect(bridge.commandLog, isNot(contains('group:updateConfig')));
        expect(msgRepo.count, 0);
      },
    );

    test(
      'limited manager member_role_updated cannot grant unheld permissions',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-manager',
            username: 'Manager',
            role: MemberRole.writer,
            permissions: const GroupMemberPermissions(manageRoles: true),
            publicKey: 'pk-manager',
            joinedAt: initialMemberJoinedAt,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-target',
            username: 'Target',
            role: MemberRole.writer,
            publicKey: 'pk-target',
            joinedAt: initialMemberJoinedAt,
          ),
        );

        listener.start(sourceController.stream);

        final sysText = jsonEncode({
          '__sys': 'member_role_updated',
          'member': {
            'peerId': 'peer-target',
            'username': 'Target',
            'role': 'writer',
            'permissions': {'deleteMessages': true},
            'publicKey': 'pk-target',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-manager',
                'role': 'writer',
                'permissions': {'manageRoles': true},
                'publicKey': 'pk-manager',
              },
              {
                'peerId': 'peer-target',
                'role': 'writer',
                'permissions': {'deleteMessages': true},
                'publicKey': 'pk-target',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-manager',
          'senderUsername': 'Manager',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final target = await groupRepo.getMember('group-1', 'peer-target');
        expect(target, isNotNull);
        expect(target!.role, MemberRole.writer);
        expect(target.permissions.deleteMessages, isNull);
        expect(bridge.commandLog, isNot(contains('group:updateConfig')));
        expect(msgRepo.count, 0);
      },
    );

    test(
      'member_role_updated refreshes myRole when self gains admin',
      () async {
        await groupRepo.updateGroup(
          testGroup.copyWith(myRole: GroupRole.member),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-self',
            username: 'Me',
            role: MemberRole.writer,
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        final selfListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
        );
        selfListener.start(sourceController.stream);

        final sysText = jsonEncode({
          '__sys': 'member_role_updated',
          'member': {'peerId': 'peer-self', 'username': 'Me', 'role': 'admin'},
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {'peerId': 'peer-self', 'role': 'admin', 'publicKey': 'pk-self'},
            ],
            'createdBy': 'peer-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': sysText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final updatedGroup = await groupRepo.getGroup('group-1');
        final updatedMember = await groupRepo.getMember('group-1', 'peer-self');
        expect(updatedGroup, isNotNull);
        expect(updatedGroup!.myRole, GroupRole.admin);
        expect(updatedMember, isNotNull);
        expect(updatedMember!.role, MemberRole.admin);

        selfListener.dispose();
      },
    );

    test(
      'older member_role_updated cannot roll back a newer role change across restart',
      () async {
        final newerListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        newerListener.start(sourceController.stream);

        const newerRoleAt = '2026-04-05T12:00:02.000Z';
        final newerRoleUpdate = jsonEncode({
          '__sys': 'member_role_updated',
          'member': {
            'peerId': 'peer-sender',
            'username': 'Sender',
            'role': 'admin',
            'publicKey': 'pk-sender',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'admin',
                'publicKey': 'pk-sender',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': newerRoleUpdate,
          'timestamp': newerRoleAt,
        });

        await Future.delayed(const Duration(milliseconds: 50));
        newerListener.dispose();

        final afterNewer = await groupRepo.getMember('group-1', 'peer-sender');
        expect(afterNewer, isNotNull);
        expect(afterNewer!.role, MemberRole.admin);
        expect(
          (await groupRepo.getGroup('group-1'))!.lastMembershipEventAt,
          DateTime.parse(newerRoleAt).toUtc(),
        );

        final restartedListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        restartedListener.start(sourceController.stream);

        final olderRoleUpdate = jsonEncode({
          '__sys': 'member_role_updated',
          'member': {
            'peerId': 'peer-sender',
            'username': 'Sender',
            'role': 'writer',
            'publicKey': 'pk-sender',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': olderRoleUpdate,
          'timestamp': '2026-04-05T12:00:01.000Z',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final persisted = await groupRepo.getMember('group-1', 'peer-sender');
        expect(persisted, isNotNull);
        expect(persisted!.role, MemberRole.admin);
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(1),
        );

        restartedListener.dispose();
      },
    );

    test(
      'older member_role_updated cannot resurrect a member removed by a newer event across restart',
      () async {
        final newerListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        newerListener.start(sourceController.stream);

        const newerRemoveAt = '2026-04-05T12:00:03.000Z';
        final newerRemove = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-sender', 'username': 'Sender'},
          'removedAt': newerRemoveAt,
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': newerRemove,
          'timestamp': newerRemoveAt,
        });

        await Future.delayed(const Duration(milliseconds: 50));
        newerListener.dispose();

        expect(await groupRepo.getMember('group-1', 'peer-sender'), isNull);
        expect(
          (await groupRepo.getGroup('group-1'))!.lastMembershipEventAt,
          DateTime.parse(newerRemoveAt).toUtc(),
        );

        final restartedListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
        );
        restartedListener.start(sourceController.stream);

        final olderRoleUpdate = jsonEncode({
          '__sys': 'member_role_updated',
          'member': {
            'peerId': 'peer-sender',
            'username': 'Sender',
            'role': 'admin',
            'publicKey': 'pk-sender',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'admin',
                'publicKey': 'pk-sender',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': olderRoleUpdate,
          'timestamp': '2026-04-05T12:00:02.000Z',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(await groupRepo.getMember('group-1', 'peer-sender'), isNull);
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(1),
        );

        restartedListener.dispose();
      },
    );

    test(
      'RP018 stale removal beats role replay and later role cannot resurrect',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-charlie',
            joinedAt: initialMemberJoinedAt,
          ),
        );

        listener.start(sourceController.stream);

        const staleRoleAt = '2026-04-05T12:00:02.000Z';
        final staleRoleUpdate = jsonEncode({
          '__sys': 'member_role_updated',
          'member': {
            'peerId': 'peer-charlie',
            'username': 'Charlie',
            'role': 'admin',
            'publicKey': 'pk-charlie',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
              {
                'peerId': 'peer-charlie',
                'role': 'admin',
                'publicKey': 'pk-charlie',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': staleRoleUpdate,
          'timestamp': staleRoleAt,
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final promoted = await groupRepo.getMember('group-1', 'peer-charlie');
        expect(promoted, isNotNull);
        expect(promoted!.role, MemberRole.admin);
        expect(
          (await groupRepo.getGroup('group-1'))!.lastMembershipEventAt,
          DateTime.parse(staleRoleAt).toUtc(),
        );

        const removalAt = '2026-04-05T12:00:01.000Z';
        final delayedRemoval = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-charlie', 'username': 'Charlie'},
          'removedAt': removalAt,
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': delayedRemoval,
          'timestamp': removalAt,
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(await groupRepo.getMember('group-1', 'peer-charlie'), isNull);
        expect(
          debugLogs.any(
            (line) => line.contains(
              'GROUP_MESSAGE_LISTENER_STALE_MEMBER_REMOVED_CONFLICT_APPLIED',
            ),
          ),
          isTrue,
        );

        const laterRoleAt = '2026-04-05T12:00:03.000Z';
        final laterRoleUpdate = jsonEncode({
          '__sys': 'member_role_updated',
          'member': {
            'peerId': 'peer-charlie',
            'username': 'Charlie',
            'role': 'writer',
            'publicKey': 'pk-charlie',
          },
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
              {
                'peerId': 'peer-charlie',
                'role': 'writer',
                'publicKey': 'pk-charlie',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': '2026-04-05T11:59:00.000Z',
          },
        });

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': laterRoleUpdate,
          'timestamp': laterRoleAt,
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(await groupRepo.getMember('group-1', 'peer-charlie'), isNull);
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(2),
        );
        expect(
          debugLogs.any(
            (line) => line.contains(
              'GROUP_MESSAGE_LISTENER_MEMBER_ROLE_UPDATE_MISSING_TARGET_IGNORED',
            ),
          ),
          isTrue,
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Media forwarding tests
  // ---------------------------------------------------------------------------
  group('media forwarding', () {
    test(
      'forwards media field from event to handleIncomingGroupMessage',
      () async {
        final mediaRepo = InMemoryMediaAttachmentRepository();
        final mediaListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
        );
        final mediaSource = StreamController<Map<String, dynamic>>.broadcast();

        mediaListener.start(mediaSource.stream);

        mediaSource.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'text': 'Photo message',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'media': [
            {
              'id': 'blob-event-1',
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

        await Future.delayed(const Duration(milliseconds: 100));

        expect(msgRepo.count, 1);
        expect(mediaRepo.count, 1);

        mediaListener.dispose();
        await mediaSource.close();
      },
    );

    test(
      'rejects invalid media before notification preview or auto-download',
      () async {
        final mediaRepo = InMemoryMediaAttachmentRepository();
        final notifService = FakeNotificationService();
        final tracker = ActiveConversationTracker();
        final mediaListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: FakeMediaFileManager(),
          notificationService: notifService,
          groupConversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
        );
        final mediaSource = StreamController<Map<String, dynamic>>.broadcast();

        mediaListener.start(mediaSource.stream);

        mediaSource.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'messageId': 'msg-invalid-media-listener',
          'text': 'Bad media',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'media': [
            {
              'id': 'blob-invalid-listener',
              'mime': 'image/svg+xml',
              'size': 12345,
              'mediaType': 'image',
              'downloadStatus': 'pending',
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            },
          ],
        });

        await Future.delayed(const Duration(milliseconds: 100));

        expect(await msgRepo.getMessage('msg-invalid-media-listener'), isNull);
        expect(mediaRepo.count, 0);
        expect(notifService.shown, isEmpty);
        expect(bridge.commandLog, isNot(contains('media:download')));

        mediaListener.dispose();
        await mediaSource.close();
      },
    );

    test(
      'rejects oversized media before notification preview or auto-download',
      () async {
        final mediaRepo = InMemoryMediaAttachmentRepository();
        final notifService = FakeNotificationService();
        final tracker = ActiveConversationTracker();
        final mediaListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: FakeMediaFileManager(),
          notificationService: notifService,
          groupConversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
        );
        final mediaSource = StreamController<Map<String, dynamic>>.broadcast();

        mediaListener.start(mediaSource.stream);

        mediaSource.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'messageId': 'msg-oversized-media-listener',
          'text': 'Huge media',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'media': [
            {
              'id': 'blob-oversized-listener',
              'mime': 'image/jpeg',
              'size': kGroupMediaPerAttachmentLimitBytes + 1,
              'mediaType': 'image',
              'downloadStatus': 'pending',
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            },
          ],
        });

        await Future.delayed(const Duration(milliseconds: 100));

        expect(
          await msgRepo.getMessage('msg-oversized-media-listener'),
          isNull,
        );
        expect(mediaRepo.count, 0);
        expect(notifService.shown, isEmpty);
        expect(bridge.commandLog, isNot(contains('media:download')));

        mediaListener.dispose();
        await mediaSource.close();
      },
    );

    test(
      'rejects hashless media before notification preview or auto-download',
      () async {
        final mediaRepo = InMemoryMediaAttachmentRepository();
        final notifService = FakeNotificationService();
        final tracker = ActiveConversationTracker();
        final mediaListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: FakeMediaFileManager(),
          notificationService: notifService,
          groupConversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
        );
        final mediaSource = StreamController<Map<String, dynamic>>.broadcast();

        mediaListener.start(mediaSource.stream);

        mediaSource.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'messageId': 'msg-hashless-media-listener',
          'text': 'Hashless media',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'media': [
            {
              'id': 'blob-hashless-listener',
              'mime': 'image/jpeg',
              'size': 12345,
              'mediaType': 'image',
              'downloadStatus': 'pending',
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            },
          ],
        });

        await Future.delayed(const Duration(milliseconds: 100));

        expect(await msgRepo.getMessage('msg-hashless-media-listener'), isNull);
        expect(mediaRepo.count, 0);
        expect(notifService.shown, isEmpty);
        expect(bridge.commandLog, isNot(contains('media:download')));

        mediaListener.dispose();
        await mediaSource.close();
      },
    );

    test('handles event without media field (backward compat)', () async {
      final mediaRepo = InMemoryMediaAttachmentRepository();
      final mediaListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
      );
      final mediaSource = StreamController<Map<String, dynamic>>.broadcast();

      mediaListener.start(mediaSource.stream);

      mediaSource.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'Text only',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 100));

      expect(msgRepo.count, 1);
      expect(mediaRepo.count, 0);

      mediaListener.dispose();
      await mediaSource.close();
    });

    test(
      'joins an in-flight shared media download for the same incoming attachment',
      () async {
        final mediaRepo = GateableMediaAttachmentRepository();
        final delayedBridge = _DelayedMediaDownloadBridge();
        final mediaFileManager = FakeMediaFileManager();
        final mediaListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: delayedBridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: mediaFileManager,
        );
        final mediaSource = StreamController<Map<String, dynamic>>.broadcast();

        final firstDownloadFuture = downloadMedia(
          bridge: delayedBridge,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: mediaFileManager,
          attachment: const MediaAttachment(
            id: 'blob-event-1',
            messageId: 'msg-group-1',
            mime: 'image/jpeg',
            size: 12345,
            mediaType: 'image',
            downloadStatus: 'pending',
            contentHash: _bytes123ContentHash,
            encryptionKeyBase64: 'key-fixture',
            encryptionNonce: 'nonce-fixture',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-03-26T10:00:00.000Z',
          ),
          contactPeerId: 'group-1',
        );
        await Future<void>.delayed(Duration.zero);

        mediaListener.start(mediaSource.stream);

        mediaSource.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'messageId': 'msg-group-1',
          'text': 'Photo message',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'media': [
            {
              'id': 'blob-event-1',
              'mime': 'image/jpeg',
              'size': 12345,
              'mediaType': 'image',
              'downloadStatus': 'pending',
              'contentHash': _bytes123ContentHash,
              'encryptionKeyBase64': 'key-fixture',
              'encryptionNonce': 'nonce-fixture',
              'encryptionScheme': 'blob_aes_256_gcm_v1',
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            },
          ],
        });

        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(mediaRepo.count, 1);
        expect(mediaRepo.downloadingUpdateCalls, 1);
        expect(
          delayedBridge.commandLog.where((cmd) => cmd == 'media:download'),
          isEmpty,
        );

        mediaRepo.firstDownloadingGate.complete();
        await Future<void>.delayed(Duration.zero);
        expect(
          delayedBridge.commandLog.where((cmd) => cmd == 'media:download'),
          hasLength(1),
        );

        delayedBridge.downloadGate.complete();
        await firstDownloadFuture;
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final savedAttachments = await mediaRepo.getAttachmentsForMessage(
          'msg-group-1',
        );
        expect(savedAttachments.single.downloadStatus, 'done');
        expect(savedAttachments.single.localPath, startsWith('media/'));
        expect(mediaRepo.downloadingUpdateCalls, 1);
        expect(
          delayedBridge.commandLog.where((cmd) => cmd == 'media:download'),
          hasLength(1),
        );

        mediaListener.dispose();
        await mediaSource.close();
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Group notifications
  // ---------------------------------------------------------------------------
  group('group notifications', () {
    test('shows notification for incoming group message', () async {
      final notifService = FakeNotificationService();
      final tracker = ActiveConversationTracker();

      final notifListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
        notificationService: notifService,
        groupConversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
      );
      notifListener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'Hello group!',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      await expectNotificationCount(notifService, 1);
      expect(notifService.shown.first.contactPeerId, 'group:group-1');
      expect(notifService.shown.first.senderUsername, 'Test Group');
      expect(notifService.shown.first.messageText, 'Sender: Hello group!');

      notifListener.dispose();
    });

    test(
      'NW-008 duplicate connection path delivery keeps one visible row and status',
      () async {
        final notifService = FakeNotificationService();
        final tracker = ActiveConversationTracker();
        const messageId = 'nw008-duplicate-connection-message';
        final firstTimestamp = DateTime.utc(2026, 5, 16, 0, 20);
        final duplicateTimestamp = firstTimestamp.add(
          const Duration(seconds: 5),
        );

        final notifListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-admin',
          notificationService: notifService,
          groupConversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
        );
        notifListener.start(sourceController.stream);

        final emitted = <GroupMessage>[];
        final sub = notifListener.groupMessageStream.listen(emitted.add);

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 8,
          'messageId': messageId,
          'text': 'NW-008 first visible delivery',
          'timestamp': firstTimestamp.toIso8601String(),
          'transportPeerId': 'peer-sender',
          'deliveryRouteKind': 'direct',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 8,
          'messageId': messageId,
          'text': 'NW-008 duplicate via reconnect path',
          'timestamp': duplicateTimestamp.toIso8601String(),
          'transportPeerId': 'peer-sender',
          'deliveryRouteKind': 'relay',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(msgRepo.count, 1);
        expect(emitted, hasLength(1));
        await expectNotificationCount(notifService, 1);
        expect(await msgRepo.getUnreadCount('group-1'), 1);

        final saved = await msgRepo.getMessage(messageId);
        expect(saved, isNotNull);
        expect(saved!.text, 'NW-008 first visible delivery');
        expect(saved.timestamp, firstTimestamp);
        expect(saved.transportPeerId, 'peer-sender');
        expect(saved.status, 'delivered');
        expect(saved.isIncoming, isTrue);
        expect(emitted.single.id, messageId);
        expect(
          notifService.shown.single.messageText,
          contains('first visible'),
        );

        await sub.cancel();
        notifListener.dispose();
      },
    );

    test('DE-005 self echo emits reconciled outbound row once', () async {
      final notifService = FakeNotificationService();
      final tracker = ActiveConversationTracker();
      const messageId = 'de005-listener-self-echo';
      final localTimestamp = DateTime.utc(2026, 5, 11, 10, 5);
      await msgRepo.saveMessage(
        GroupMessage(
          id: messageId,
          groupId: 'group-1',
          senderPeerId: 'peer-sender',
          transportPeerId: 'peer-sender',
          senderUsername: 'Sender',
          text: 'Local listener pending text',
          timestamp: localTimestamp,
          keyGeneration: 1,
          status: 'pending',
          isIncoming: false,
          createdAt: localTimestamp,
          wireEnvelope: '{"cmd":"group:publish"}',
          inboxRetryPayload: '{"cmd":"group:inboxStore"}',
        ),
      );

      final selfListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-sender',
        notificationService: notifService,
        groupConversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
      );
      final emitted = <GroupMessage>[];
      final subscription = selfListener.groupMessageStream.listen(emitted.add);
      selfListener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 1,
        'text': 'Local listener pending text',
        'timestamp': localTimestamp
            .add(const Duration(seconds: 5))
            .toIso8601String(),
        'messageId': messageId,
        'transportPeerId': 'peer-sender',
      });
      await Future.delayed(const Duration(milliseconds: 50));

      expect(emitted, hasLength(1));
      expect(emitted.single.id, messageId);
      expect(emitted.single.isIncoming, isFalse);
      expect(emitted.single.status, 'sent');
      expect(msgRepo.count, 1);
      final saved = await msgRepo.getMessage(messageId);
      expect(saved, isNotNull);
      expect(saved!.isIncoming, isFalse);
      expect(saved.status, 'sent');
      expect(await msgRepo.getUnreadCount('group-1'), 0);
      expect(notifService.shown, isEmpty);

      await subscription.cancel();
      selfListener.dispose();
    });

    test(
      'replayed duplicate group message does not create a second local notification',
      () async {
        final notifService = FakeNotificationService();
        final tracker = ActiveConversationTracker();

        final notifListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
          notificationService: notifService,
          groupConversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
        );
        notifListener.start(sourceController.stream);

        final message = {
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'text': 'Hello group!',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'messageId': 'group-replay-1',
        };

        sourceController.add(message);

        await Future.delayed(const Duration(milliseconds: 50));

        await expectNotificationCount(notifService, 1);
        expect(msgRepo.count, 1);

        await notifListener.handleReplayEnvelope(message);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(
          notifService.shown,
          hasLength(1),
          reason: 'Replay must not create a second local notification',
        );
        expect(
          msgRepo.count,
          1,
          reason: 'Replay must not persist a second message row',
        );

        notifListener.dispose();
      },
    );

    test(
      'GP-025 LP013 duplicate PubSub delivery preserves first row and notification state',
      () async {
        final notifService = FakeNotificationService();
        final tracker = ActiveConversationTracker();
        final mediaRepo = InMemoryMediaAttachmentRepository();
        const messageId = 'lp013-live-duplicate-message';
        final firstTimestamp = DateTime.utc(2026, 4, 30, 22, 50);
        final conflictingTimestamp = firstTimestamp.add(
          const Duration(minutes: 1),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-self',
            username: 'Self',
            role: MemberRole.writer,
            publicKey: 'pk-self',
            joinedAt: initialMemberJoinedAt,
          ),
        );

        final notifListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
          notificationService: notifService,
          groupConversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          mediaAttachmentRepo: mediaRepo,
        );
        notifListener.start(sourceController.stream);

        final emitted = <GroupMessage>[];
        final sub = notifListener.groupMessageStream.listen(emitted.add);

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 7,
          'messageId': messageId,
          'text': 'Trusted first content',
          'timestamp': firstTimestamp.toIso8601String(),
          'quotedMessageId': 'lp013-parent-first',
          'media': [
            {
              'id': 'lp013-media-1',
              'mime': 'image/png',
              'size': 2048,
              'mediaType': 'image',
              'downloadStatus': 'pending',
              'contentHash': _validContentHash,
              'encryptionKeyBase64': 'key-fixture',
              'encryptionNonce': 'nonce-fixture',
              'encryptionScheme': 'blob_aes_256_gcm_v1',
              'createdAt': firstTimestamp.toIso8601String(),
            },
          ],
        });

        await Future.delayed(const Duration(milliseconds: 50));

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 9,
          'messageId': messageId,
          'text': 'Conflicting duplicate content',
          'timestamp': conflictingTimestamp.toIso8601String(),
          'quotedMessageId': 'lp013-parent-conflicting',
          'media': [
            {
              'id': 'lp013-media-1',
              'mime': 'image/jpeg',
              'size': 4096,
              'mediaType': 'image',
              'downloadStatus': 'pending',
              'contentHash':
                  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              'encryptionKeyBase64': 'other-key-fixture',
              'encryptionNonce': 'other-nonce-fixture',
              'encryptionScheme': 'blob_aes_256_gcm_v1',
              'createdAt': conflictingTimestamp.toIso8601String(),
            },
          ],
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(msgRepo.count, 1);
        expect(emitted, hasLength(1));
        await expectNotificationCount(notifService, 1);
        expect(await msgRepo.getUnreadCount('group-1'), 1);

        final saved = await msgRepo.getMessage(messageId);
        expect(saved, isNotNull);
        expect(saved!.text, 'Trusted first content');
        expect(saved.timestamp, firstTimestamp);
        expect(saved.quotedMessageId, 'lp013-parent-first');
        expect(saved.keyGeneration, 7);
        expect(saved.status, 'delivered');

        final attachments = await mediaRepo.getAttachmentsForMessage(messageId);
        expect(attachments, hasLength(1));
        expect(attachments.single.id, 'lp013-media-1');
        expect(attachments.single.mime, 'image/png');
        expect(attachments.single.size, 2048);
        expect(attachments.single.contentHash, _validContentHash);

        expect(emitted.single.id, messageId);
        expect(emitted.single.text, 'Trusted first content');
        expect(notifService.shown.single.contactPeerId, 'group:group-1');
        expect(notifService.shown.single.messageText, contains('Trusted'));

        await sub.cancel();
        notifListener.dispose();
      },
    );

    test(
      'suppresses local notification when a recent remote push already announced the same group message',
      () async {
        final notifService = FakeNotificationService();
        final tracker = ActiveConversationTracker();
        final gate = RecentRemoteNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/group-listener-remote-push-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        addTearDown(gate.clear);
        await gate.markAnnouncement(
          payload: 'group:group-1|message:group-msg-1',
          messageId: 'group-msg-1',
        );

        final notifListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
          notificationService: notifService,
          groupConversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          remoteNotificationGate: gate,
        );
        notifListener.start(sourceController.stream);

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'text': 'Hello group!',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'messageId': 'group-msg-1',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(notifService.shown, isEmpty);
        expect(msgRepo.count, 1);

        notifListener.dispose();
      },
    );

    test('suppresses notification when viewing group conversation', () async {
      final notifService = FakeNotificationService();
      final tracker = ActiveConversationTracker();
      tracker.setActive('group:group-1');

      final notifListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
        notificationService: notifService,
        groupConversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.resumed,
      );
      notifListener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'Hello group!',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifService.shown, isEmpty);

      notifListener.dispose();
    });

    test(
      'suppresses local notification for muted groups but still persists the message',
      () async {
        final notifService = FakeNotificationService();
        final tracker = ActiveConversationTracker();

        await groupRepo.updateGroup(testGroup.copyWith(isMuted: true));

        final notifListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-self',
          notificationService: notifService,
          groupConversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
        );
        notifListener.start(sourceController.stream);

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'text': 'Muted group message',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(notifService.shown, isEmpty);
        expect(msgRepo.count, 1);
        final latest = await msgRepo.getLatestMessage('group-1');
        expect(latest, isNotNull);
        expect(latest!.text, 'Muted group message');

        notifListener.dispose();
      },
    );

    test(
      'UP-011 muted group persists unread delivery without local notification',
      () async {
        final notifService = FakeNotificationService();
        final tracker = ActiveConversationTracker();

        await groupRepo.updateGroup(testGroup.copyWith(isMuted: true));

        final notifListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'peer-admin',
          notificationService: notifService,
          groupConversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
        );
        notifListener.start(sourceController.stream);

        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'text': 'UP-011 muted delivery',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'messageId': 'up011-muted-delivery',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(notifService.shown, isEmpty);
        expect(notifService.shownGeneric, isEmpty);
        expect(msgRepo.count, 1);
        expect(await msgRepo.getUnreadCount('group-1'), 1);
        final latest = await msgRepo.getLatestMessage('group-1');
        expect(latest, isNotNull);
        expect(latest!.text, 'UP-011 muted delivery');

        notifListener.dispose();
      },
    );

    test('does not notify for own messages', () async {
      final notifService = FakeNotificationService();
      final tracker = ActiveConversationTracker();

      final notifListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-sender',
        notificationService: notifService,
        groupConversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
      );
      notifListener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'My own message',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifService.shown, isEmpty);

      notifListener.dispose();
    });

    test('does not notify after self-removal deletes the group', () async {
      final notifService = FakeNotificationService();
      final tracker = ActiveConversationTracker();
      final selfJoinedAt = DateTime.utc(2026, 4, 5, 12);
      final removedAt = DateTime.utc(2026, 4, 5, 12, 0, 1);

      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-self',
          username: 'Me',
          role: MemberRole.writer,
          joinedAt: selfJoinedAt,
        ),
      );
      await groupRepo.updateGroup(testGroup.copyWith(myRole: GroupRole.member));

      final notifListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
        notificationService: notifService,
        groupConversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
      );
      notifListener.start(sourceController.stream);

      final removedGroups = <String>[];
      final sub = notifListener.groupRemovedStream.listen(removedGroups.add);

      final sysText = jsonEncode({
        '__sys': 'member_removed',
        'member': {'peerId': 'peer-self', 'username': 'Me'},
        'removedAt': removedAt.toIso8601String(),
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-admin', 'role': 'admin'},
          ],
          'createdBy': 'peer-admin',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'text': sysText,
        'timestamp': removedAt.toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(await groupRepo.getGroup('group-1'), isNull);
      expect(removedGroups, <String>['group-1']);
      expect(
        bridge.commandLog.where((command) => command == 'group:leave'),
        hasLength(1),
      );

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'After removal',
        'messageId': 'post-removal-message-1',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifService.shown, isEmpty);
      expect(msgRepo.count, 0);

      await sub.cancel();
      notifListener.dispose();
    });

    test('does not notify when notification deps are null', () async {
      // Default listener without notification params (current behavior)
      listener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'No crash please',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      // No crash, message still persisted
      expect(msgRepo.count, 1);
    });

    test('shows notification when viewing different group', () async {
      final notifService = FakeNotificationService();
      final tracker = ActiveConversationTracker();
      tracker.setActive('group:other-group');

      final notifListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        getSelfPeerId: () async => 'peer-self',
        notificationService: notifService,
        groupConversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.resumed,
      );
      notifListener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': 'Hello!',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      await expectNotificationCount(notifService, 1);

      notifListener.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Group reactions
  // ---------------------------------------------------------------------------
  group('group reactions', () {
    late FakeReactionRepository reactionRepo;
    late StreamController<Map<String, dynamic>> reactionSource;

    setUp(() {
      reactionRepo = FakeReactionRepository();
      reactionSource = StreamController<Map<String, dynamic>>.broadcast();
    });

    tearDown(() {
      reactionSource.close();
    });

    test(
      'emits ReactionChange on groupReactionChangeStream for incoming add reaction',
      () async {
        final rxnListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          reactionRepo: reactionRepo,
        );

        rxnListener.start(
          sourceController.stream,
          incomingGroupReactions: reactionSource.stream,
        );

        final changes = <ReactionChange>[];
        final sub = rxnListener.groupReactionChangeStream.listen(changes.add);

        reactionSource.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'reaction': jsonEncode({
            'id': 'rxn-1',
            'messageId': 'msg-1',
            'emoji': '\u{1F44D}',
            'action': 'add',
            'senderPeerId': 'peer-sender',
            'timestamp': '2026-01-01T00:00:00.000Z',
          }),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(changes.length, 1);
        expect(changes.first.type, ReactionChangeType.upserted);
        expect(changes.first.messageId, 'msg-1');
        expect(changes.first.reaction?.emoji, '\u{1F44D}');
        expect(reactionRepo.saveReactionCallCount, 1);

        await sub.cancel();
        rxnListener.dispose();
      },
    );

    test('emits removal ReactionChange when action is remove', () async {
      final rxnListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        reactionRepo: reactionRepo,
      );

      rxnListener.start(
        sourceController.stream,
        incomingGroupReactions: reactionSource.stream,
      );

      final changes = <ReactionChange>[];
      final sub = rxnListener.groupReactionChangeStream.listen(changes.add);

      reactionSource.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'reaction': jsonEncode({
          'id': 'rxn-1',
          'messageId': 'msg-1',
          'emoji': '\u{1F44D}',
          'action': 'remove',
          'senderPeerId': 'peer-sender',
          'timestamp': '2026-01-01T00:00:00.000Z',
        }),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(changes.length, 1);
      expect(changes.first.type, ReactionChangeType.removed);
      expect(changes.first.messageId, 'msg-1');
      expect(changes.first.senderPeerId, 'peer-sender');

      await sub.cancel();
      rxnListener.dispose();
    });

    test(
      'SV-002 removed old-key reaction event does not mutate visible reactions',
      () async {
        const existing = MessageReaction(
          id: 'sv002-existing-reaction',
          messageId: 'sv002-target',
          emoji: '✅',
          senderPeerId: 'peer-admin',
          timestamp: '2026-05-14T03:00:00.000Z',
          createdAt: '2026-05-14T03:00:00.000Z',
        );
        await reactionRepo.saveReaction(existing);
        await groupRepo.removeMember('group-1', 'peer-sender');

        final rxnListener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          bridge: bridge,
          reactionRepo: reactionRepo,
        );

        rxnListener.start(
          sourceController.stream,
          incomingGroupReactions: reactionSource.stream,
        );

        final changes = <ReactionChange>[];
        final sub = rxnListener.groupReactionChangeStream.listen(changes.add);

        reactionSource.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'transportPeerId': 'peer-sender',
          'reaction': jsonEncode({
            'id': 'sv002-removed-reaction',
            'messageId': 'sv002-target',
            'emoji': '🔥',
            'action': 'add',
            'senderPeerId': 'peer-sender',
            'timestamp': '2026-05-14T03:00:01.000Z',
          }),
        });

        await Future.delayed(const Duration(milliseconds: 50));

        expect(changes, isEmpty);
        expect(await reactionRepo.getReactionsForMessage('sv002-target'), [
          existing,
        ]);
        expect(reactionRepo.saveReactionCallCount, 1);
        expect(reactionRepo.removeReactionCallCount, 0);

        await sub.cancel();
        rxnListener.dispose();
      },
    );

    test('ignores reaction when reactionRepo is null', () async {
      final noRepoListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        // No reactionRepo
      );

      noRepoListener.start(
        sourceController.stream,
        incomingGroupReactions: reactionSource.stream,
      );

      final changes = <ReactionChange>[];
      final sub = noRepoListener.groupReactionChangeStream.listen(changes.add);

      reactionSource.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'reaction': jsonEncode({
          'id': 'rxn-1',
          'messageId': 'msg-1',
          'emoji': '\u{1F44D}',
          'action': 'add',
          'senderPeerId': 'peer-sender',
          'timestamp': '2026-01-01T00:00:00.000Z',
        }),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(changes, isEmpty);

      await sub.cancel();
      noRepoListener.dispose();
    });

    test('ignores malformed reaction data', () async {
      final rxnListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        reactionRepo: reactionRepo,
      );

      rxnListener.start(
        sourceController.stream,
        incomingGroupReactions: reactionSource.stream,
      );

      final changes = <ReactionChange>[];
      final sub = rxnListener.groupReactionChangeStream.listen(changes.add);

      // Empty groupId and senderId → malformed, should be ignored
      reactionSource.add({
        'groupId': '',
        'senderId': '',
        'reaction': jsonEncode({
          'id': 'rxn-1',
          'messageId': 'msg-1',
          'emoji': '\u{1F44D}',
          'action': 'add',
          'senderPeerId': 'peer-sender',
          'timestamp': '2026-01-01T00:00:00.000Z',
        }),
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(changes, isEmpty);

      await sub.cancel();
      rxnListener.dispose();
    });
  });

  group('group_dissolved system messages', () {
    test(
      'marks the group dissolved, stores a timeline event, and leaves the topic',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            joinedAt: initialMemberJoinedAt,
          ),
        );
        listener.start(sourceController.stream);

        sourceController.add({
          'groupId': 'group-1',
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

        await Future.delayed(const Duration(milliseconds: 50));

        final updated = await groupRepo.getGroup('group-1');
        expect(updated, isNotNull);
        expect(updated!.isDissolved, isTrue);
        expect(updated.dissolvedAt, DateTime.utc(2026, 4, 5, 12, 0, 0));
        expect(updated.dissolvedBy, 'peer-admin');

        final saved = await msgRepo.getLatestMessage('group-1');
        expect(saved, isNotNull);
        expect(saved!.id.startsWith('sys-group_dissolved:group-1:'), isTrue);
        expect(saved.text, 'Admin dissolved the group');
        expect(bridge.commandLog, contains('group:leave'));
      },
    );

    test('LP003 replayed group_dissolved dispatches one group leave', () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          joinedAt: initialMemberJoinedAt,
        ),
      );

      await listener.handleReplayEnvelope({
        'groupId': 'group-1',
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

      final updated = await groupRepo.getGroup('group-1');
      expect(updated, isNotNull);
      expect(updated!.isDissolved, isTrue);
      expect(
        bridge.commandLog.where((command) => command == 'group:leave'),
        hasLength(1),
      );
      final saved = await msgRepo.getLatestMessage('group-1');
      expect(saved, isNotNull);
      expect(saved!.id.startsWith('sys-group_dissolved:group-1:'), isTrue);
    });

    test('replayed group_dissolved is idempotent', () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          joinedAt: initialMemberJoinedAt,
        ),
      );
      await listener.handleReplayEnvelope({
        'groupId': 'group-1',
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

      await listener.handleReplayEnvelope({
        'groupId': 'group-1',
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

      final messages = await msgRepo.getMessagesPage('group-1');
      final dissolvedMessages = messages
          .where((message) => message.id.startsWith('sys-group_dissolved:'))
          .toList();
      expect(dissolvedMessages, hasLength(1));

      final leaveCalls = bridge.commandLog
          .where((command) => command == 'group:leave')
          .length;
      expect(leaveCalls, 1);
    });

    test(
      'old system events after group_dissolved do not mutate metadata, members, keys, or visible messages',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            joinedAt: initialMemberJoinedAt,
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 1,
            encryptedKey: 'epoch-1-key',
            createdAt: DateTime.utc(2026, 4, 5, 11, 59),
          ),
        );

        await listener.handleReplayEnvelope({
          'groupId': 'group-1',
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

        final staleEvents = <Map<String, dynamic>>[
          {
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({
              '__sys': 'group_metadata_updated',
              'updatedAt': '2026-04-05T11:59:00.000Z',
              'groupConfig': {
                'name': 'Resurrected Name',
                'groupType': 'chat',
                'description': 'Should not return',
                'metadataUpdatedAt': '2026-04-05T11:59:00.000Z',
                'members': [
                  {
                    'peerId': 'peer-admin',
                    'role': 'admin',
                    'publicKey': 'pk-admin',
                  },
                  {
                    'peerId': 'peer-sender',
                    'role': 'writer',
                    'publicKey': 'pk-sender',
                  },
                ],
                'createdBy': 'peer-admin',
                'createdAt': initialGroupCreatedAt.toIso8601String(),
              },
            }),
            'timestamp': '2026-04-05T11:59:00.000Z',
          },
          {
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({
              '__sys': 'member_added',
              'member': {
                'peerId': 'peer-resurrected',
                'username': 'Resurrected',
                'role': 'writer',
                'publicKey': 'pk-resurrected',
              },
              'groupConfig': {
                'name': 'Resurrected Name',
                'groupType': 'chat',
                'members': [
                  {
                    'peerId': 'peer-admin',
                    'role': 'admin',
                    'publicKey': 'pk-admin',
                  },
                  {
                    'peerId': 'peer-resurrected',
                    'role': 'writer',
                    'publicKey': 'pk-resurrected',
                  },
                ],
                'createdBy': 'peer-admin',
                'createdAt': initialGroupCreatedAt.toIso8601String(),
              },
            }),
            'timestamp': '2026-04-05T11:59:01.000Z',
          },
          {
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({
              '__sys': 'member_role_updated',
              'member': {
                'peerId': 'peer-sender',
                'username': 'Sender',
                'role': 'admin',
                'publicKey': 'pk-sender',
              },
              'groupConfig': {
                'name': 'Resurrected Name',
                'groupType': 'chat',
                'members': [
                  {
                    'peerId': 'peer-admin',
                    'role': 'admin',
                    'publicKey': 'pk-admin',
                  },
                  {
                    'peerId': 'peer-sender',
                    'role': 'admin',
                    'publicKey': 'pk-sender',
                  },
                ],
                'createdBy': 'peer-admin',
                'createdAt': initialGroupCreatedAt.toIso8601String(),
              },
            }),
            'timestamp': '2026-04-05T11:59:02.000Z',
          },
          {
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({'__sys': 'key_rotated', 'newKeyEpoch': 2}),
            'timestamp': '2026-04-05T11:59:03.000Z',
          },
        ];

        for (final event in staleEvents) {
          await listener.handleReplayEnvelope(event);
        }

        final group = await groupRepo.getGroup('group-1');
        expect(group, isNotNull);
        expect(group!.isDissolved, isTrue);
        expect(group.name, 'Test Group');
        expect(group.description, isNull);
        expect(group.lastMetadataEventAt, isNull);

        expect(
          await groupRepo.getMember('group-1', 'peer-resurrected'),
          isNull,
        );
        final sender = await groupRepo.getMember('group-1', 'peer-sender');
        expect(sender, isNotNull);
        expect(sender!.role, MemberRole.writer);

        final latestKey = await groupRepo.getLatestKey('group-1');
        expect(latestKey, isNotNull);
        expect(latestKey!.keyGeneration, 1);
        expect(latestKey.encryptedKey, 'epoch-1-key');

        final messages = await msgRepo.getMessagesPage('group-1');
        expect(messages, hasLength(1));
        expect(messages.single.text, 'Admin dissolved the group');
        expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      },
    );

    test(
      'old system events for a locally deleted group do not recreate group row or visible message',
      () async {
        await groupRepo.deleteGroup('group-1');
        await groupRepo.removeAllMembers('group-1');
        await groupRepo.removeAllKeys('group-1');

        final deletedGroupEvents = <Map<String, dynamic>>[
          {
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({
              '__sys': 'group_metadata_updated',
              'updatedAt': '2026-04-05T12:01:00.000Z',
              'groupConfig': {
                'name': 'Deleted Group Returned',
                'groupType': 'chat',
                'description': 'Should not be visible',
                'metadataUpdatedAt': '2026-04-05T12:01:00.000Z',
                'members': [
                  {
                    'peerId': 'peer-admin',
                    'role': 'admin',
                    'publicKey': 'pk-admin',
                  },
                ],
                'createdBy': 'peer-admin',
                'createdAt': initialGroupCreatedAt.toIso8601String(),
              },
            }),
            'timestamp': '2026-04-05T12:01:00.000Z',
          },
          {
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({
              '__sys': 'member_added',
              'member': {
                'peerId': 'peer-returned',
                'username': 'Returned',
                'role': 'writer',
                'publicKey': 'pk-returned',
              },
              'groupConfig': {
                'name': 'Deleted Group Returned',
                'groupType': 'chat',
                'members': [
                  {
                    'peerId': 'peer-admin',
                    'role': 'admin',
                    'publicKey': 'pk-admin',
                  },
                  {
                    'peerId': 'peer-returned',
                    'role': 'writer',
                    'publicKey': 'pk-returned',
                  },
                ],
                'createdBy': 'peer-admin',
                'createdAt': initialGroupCreatedAt.toIso8601String(),
              },
            }),
            'timestamp': '2026-04-05T12:01:01.000Z',
          },
          {
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({'__sys': 'key_rotated', 'newKeyEpoch': 2}),
            'timestamp': '2026-04-05T12:01:02.000Z',
          },
        ];

        for (final event in deletedGroupEvents) {
          await listener.handleReplayEnvelope(event);
        }

        expect(await groupRepo.getGroup('group-1'), isNull);
        expect(await groupRepo.getMembers('group-1'), isEmpty);
        expect(await groupRepo.getLatestKey('group-1'), isNull);
        expect(await msgRepo.getMessagesPage('group-1'), isEmpty);
        expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      },
    );

    test('unauthorized group_dissolved is ignored', () async {
      listener.start(sourceController.stream);

      sourceController.add({
        'groupId': 'group-1',
        'senderId': 'peer-sender',
        'senderUsername': 'Sender',
        'keyEpoch': 0,
        'text': jsonEncode({
          '__sys': 'group_dissolved',
          'dissolvedAt': '2026-04-05T12:00:00.000Z',
          'dissolvedBy': 'peer-sender',
        }),
        'timestamp': '2026-04-05T12:00:00.000Z',
      });

      await Future.delayed(const Duration(milliseconds: 50));

      final group = await groupRepo.getGroup('group-1');
      expect(group, isNotNull);
      expect(group!.isDissolved, isFalse);
      expect(await msgRepo.getLatestMessage('group-1'), isNull);
      expect(bridge.commandLog, isNot(contains('group:leave')));
    });

    test(
      'stored creator who is no longer admin cannot dissolve the group',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.writer,
            joinedAt: initialMemberJoinedAt,
          ),
        );

        listener.start(sourceController.stream);

        sourceController.add({
          'groupId': 'group-1',
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

        await Future.delayed(const Duration(milliseconds: 50));

        final group = await groupRepo.getGroup('group-1');
        expect(group, isNotNull);
        expect(group!.isDissolved, isFalse);
        expect(await msgRepo.getLatestMessage('group-1'), isNull);
        expect(bridge.commandLog, isNot(contains('group:leave')));
      },
    );

    test(
      'RP005 demoted creator receive-side mutations are rejected before side effects',
      () async {
        bridge.responses['payload.verify'] = {'ok': true, 'valid': true};
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.writer,
            publicKey: 'pk-admin',
            joinedAt: initialMemberJoinedAt,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-target',
            username: 'Target',
            role: MemberRole.writer,
            publicKey: 'pk-target',
            joinedAt: initialMemberJoinedAt,
          ),
        );

        listener.start(sourceController.stream);

        final metadataUpdatedAt = DateTime.utc(2026, 4, 5, 12, 0, 3);
        final staleMutationEvents = <Map<String, dynamic>>[
          {
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({
              '__sys': 'member_added',
              'member': {
                'peerId': 'peer-late',
                'username': 'Late',
                'role': 'writer',
                'publicKey': 'pk-late',
              },
              'groupConfig': {
                'name': 'Stale Add',
                'groupType': 'chat',
                'members': [
                  {
                    'peerId': 'peer-admin',
                    'role': 'writer',
                    'publicKey': 'pk-admin',
                  },
                  {
                    'peerId': 'peer-late',
                    'role': 'writer',
                    'publicKey': 'pk-late',
                  },
                ],
                'createdBy': 'peer-admin',
                'createdAt': initialGroupCreatedAt.toIso8601String(),
              },
            }),
            'timestamp': '2026-04-05T12:00:00.000Z',
          },
          {
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({
              '__sys': 'member_removed',
              'member': {'peerId': 'peer-target', 'username': 'Target'},
              'removedAt': '2026-04-05T12:00:01.000Z',
              'groupConfig': {
                'name': 'Stale Remove',
                'groupType': 'chat',
                'members': [
                  {
                    'peerId': 'peer-admin',
                    'role': 'writer',
                    'publicKey': 'pk-admin',
                  },
                ],
                'createdBy': 'peer-admin',
                'createdAt': initialGroupCreatedAt.toIso8601String(),
              },
            }),
            'timestamp': '2026-04-05T12:00:01.000Z',
          },
          {
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode({
              '__sys': 'member_role_updated',
              'member': {
                'peerId': 'peer-target',
                'username': 'Target',
                'role': 'admin',
                'publicKey': 'pk-target',
              },
              'groupConfig': {
                'name': 'Stale Role',
                'groupType': 'chat',
                'members': [
                  {
                    'peerId': 'peer-admin',
                    'role': 'writer',
                    'publicKey': 'pk-admin',
                  },
                  {
                    'peerId': 'peer-target',
                    'role': 'admin',
                    'publicKey': 'pk-target',
                  },
                ],
                'createdBy': 'peer-admin',
                'createdAt': initialGroupCreatedAt.toIso8601String(),
              },
            }),
            'timestamp': '2026-04-05T12:00:02.000Z',
          },
          {
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'keyEpoch': 0,
            'text': jsonEncode(
              signedMetadataSystemPayload(
                updatedAt: metadataUpdatedAt,
                groupConfig: buildMetadataConfig(
                  updatedAt: metadataUpdatedAt,
                  name: 'Stale Metadata',
                  description: 'Should not apply',
                ),
              ),
            ),
            'timestamp': metadataUpdatedAt.toIso8601String(),
          },
        ];

        for (final event in staleMutationEvents) {
          sourceController.add(event);
        }
        await Future.delayed(const Duration(milliseconds: 100));

        final group = await groupRepo.getGroup('group-1');
        expect(group, isNotNull);
        expect(group!.name, 'Test Group');
        expect(group.description, isNull);
        expect(group.lastMembershipEventAt, isNull);
        expect(group.lastMetadataEventAt, isNull);
        expect(await groupRepo.getMember('group-1', 'peer-late'), isNull);
        final admin = await groupRepo.getMember('group-1', 'peer-admin');
        expect(admin, isNotNull);
        expect(admin!.role, MemberRole.writer);
        final target = await groupRepo.getMember('group-1', 'peer-target');
        expect(target, isNotNull);
        expect(target!.role, MemberRole.writer);
        expect(msgRepo.count, 0);
        expect(bridge.commandLog, isNot(contains('payload.verify')));
        expect(bridge.commandLog, isNot(contains('group:updateConfig')));
      },
    );
  });

  group('duplicate shipped system event replay', () {
    int updateConfigCallCount() => bridge.commandLog
        .where((command) => command == 'group:updateConfig')
        .length;

    test(
      'duplicate members_added keeps one timeline row and member set',
      () async {
        listener.start(sourceController.stream);

        const eventAt = '2026-04-05T12:10:00.000Z';
        final sysText = jsonEncode({
          '__sys': 'members_added',
          'members': [
            {
              'peerId': 'peer-dave',
              'username': 'Dave',
              'role': 'writer',
              'publicKey': 'pk-dave',
            },
            {
              'peerId': 'peer-eve',
              'username': 'Eve',
              'role': 'writer',
              'publicKey': 'pk-eve',
            },
          ],
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
              {
                'peerId': 'peer-sender',
                'role': 'writer',
                'publicKey': 'pk-sender',
              },
              {'peerId': 'peer-dave', 'role': 'writer', 'publicKey': 'pk-dave'},
              {'peerId': 'peer-eve', 'role': 'writer', 'publicKey': 'pk-eve'},
            ],
            'createdBy': 'peer-admin',
            'createdAt': initialGroupCreatedAt.toIso8601String(),
          },
        });
        final duplicateEvent = {
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'messageId': 'members-added-replay-1',
          'text': sysText,
          'timestamp': eventAt,
        };

        sourceController.add(duplicateEvent);
        sourceController.add(duplicateEvent);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(await groupRepo.getMember('group-1', 'peer-dave'), isNotNull);
        expect(await groupRepo.getMember('group-1', 'peer-eve'), isNotNull);
        expect(msgRepo.count, 1);
        expect(
          (await msgRepo.getLatestMessage('group-1'))!.text,
          'Admin added Dave and Eve',
        );
        expect(updateConfigCallCount(), 1);
      },
    );

    test(
      'duplicate non-self member_removed keeps one timeline row and removal',
      () async {
        listener.start(sourceController.stream);

        const eventAt = '2026-04-05T12:11:00.000Z';
        final sysText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': 'peer-sender', 'username': 'Sender'},
          'groupConfig': {
            'name': 'Test Group',
            'groupType': 'chat',
            'members': [
              {
                'peerId': 'peer-admin',
                'role': 'admin',
                'publicKey': 'pk-admin',
              },
            ],
            'createdBy': 'peer-admin',
            'createdAt': initialGroupCreatedAt.toIso8601String(),
          },
        });
        final duplicateEvent = {
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'messageId': 'member-removed-replay-1',
          'text': sysText,
          'timestamp': eventAt,
        };

        sourceController.add(duplicateEvent);
        sourceController.add(duplicateEvent);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(await groupRepo.getMember('group-1', 'peer-sender'), isNull);
        expect(msgRepo.count, 1);
        expect(
          (await msgRepo.getLatestMessage('group-1'))!.text,
          'Admin removed Sender',
        );
        expect(updateConfigCallCount(), 1);
        expect(bridge.commandLog, isNot(contains('group:leave')));
      },
    );

    test('duplicate member_role_updated keeps one role timeline row', () async {
      listener.start(sourceController.stream);

      const eventAt = '2026-04-05T12:12:00.000Z';
      final sysText = jsonEncode({
        '__sys': 'member_role_updated',
        'member': {
          'peerId': 'peer-sender',
          'username': 'Sender',
          'role': 'admin',
          'publicKey': 'pk-sender',
        },
        'groupConfig': {
          'name': 'Test Group',
          'groupType': 'chat',
          'members': [
            {'peerId': 'peer-admin', 'role': 'admin', 'publicKey': 'pk-admin'},
            {
              'peerId': 'peer-sender',
              'role': 'admin',
              'publicKey': 'pk-sender',
            },
          ],
          'createdBy': 'peer-admin',
          'createdAt': initialGroupCreatedAt.toIso8601String(),
        },
      });
      final duplicateEvent = {
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'messageId': 'member-role-updated-replay-1',
        'text': sysText,
        'timestamp': eventAt,
      };

      sourceController.add(duplicateEvent);
      sourceController.add(duplicateEvent);
      await Future.delayed(const Duration(milliseconds: 50));

      final updated = await groupRepo.getMember('group-1', 'peer-sender');
      expect(updated, isNotNull);
      expect(updated!.role, MemberRole.admin);
      expect(msgRepo.count, 1);
      expect(
        (await msgRepo.getLatestMessage('group-1'))!.text,
        'Admin made Sender an admin',
      );
      expect(updateConfigCallCount(), 1);
    });

    test(
      'duplicate group_metadata_updated keeps one metadata timeline row',
      () async {
        await saveTrustedAdminMember();
        bridge.responses['payload.verify'] = {'ok': true, 'valid': true};
        listener.start(sourceController.stream);

        final eventAt = DateTime.parse('2026-04-05T12:13:00.000Z');
        final groupConfig = buildMetadataConfig(updatedAt: eventAt);
        final sysText = jsonEncode(
          signedMetadataSystemPayload(
            updatedAt: eventAt,
            groupConfig: groupConfig,
          ),
        );
        final duplicateEvent = {
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'messageId': 'metadata-updated-replay-1',
          'text': sysText,
          'timestamp': eventAt.toUtc().toIso8601String(),
        };

        sourceController.add(duplicateEvent);
        sourceController.add(duplicateEvent);
        await Future.delayed(const Duration(milliseconds: 50));

        final group = await groupRepo.getGroup('group-1');
        expect(group, isNotNull);
        expect(group!.name, 'Renamed Group');
        expect(group.description, 'Fresh description');
        expect(msgRepo.count, 1);
        expect(
          (await msgRepo.getLatestMessage('group-1'))!.text,
          'Admin updated the group details',
        );
        expect(updateConfigCallCount(), 1);
      },
    );

    test('duplicate key_rotated system event stays non-durable', () async {
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start(sourceController.stream);

      const eventAt = '2026-04-05T12:14:00.000Z';
      final signedKeyRotatedPayload = await signedAuditSystemPayload(
        transitionType: 'key_rotated',
        sourceEventId: 'key-rotated-replay-1',
        eventAt: DateTime.parse(eventAt),
        systemPayload: {'__sys': 'key_rotated', 'newKeyEpoch': 2},
      );
      final duplicateEvent = {
        'groupId': 'group-1',
        'senderId': 'peer-admin',
        'senderUsername': 'Admin',
        'keyEpoch': 0,
        'messageId': 'key-rotated-replay-1',
        'text': jsonEncode(signedKeyRotatedPayload),
        'timestamp': eventAt,
      };

      sourceController.add(duplicateEvent);
      sourceController.add(duplicateEvent);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(msgRepo.count, 0);
      expect(eventLog.entries, hasLength(1));
      expect(eventLog.entries.single['eventType'], 'key_rotated');
      expect(eventLog.entries.single['sourceEventId'], 'key-rotated-replay-1');
    });
  });

  test(
    'ML-013 unauthorized writer mutation system events leave local state and bridge unchanged',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          publicKey: 'pk-admin',
          joinedAt: initialMemberJoinedAt,
        ),
      );
      listener.start(sourceController.stream);

      final mutationEvents = <({String name, String text})>[
        (
          name: 'member_added',
          text: jsonEncode({
            '__sys': 'member_added',
            'member': {
              'peerId': 'peer-rp004-added',
              'username': 'Added',
              'role': 'writer',
              'publicKey': 'pk-added',
            },
            'groupConfig': {
              'name': 'Test Group',
              'groupType': 'chat',
              'members': [
                {
                  'peerId': 'peer-admin',
                  'role': 'admin',
                  'publicKey': 'pk-admin',
                },
                {
                  'peerId': 'peer-sender',
                  'role': 'writer',
                  'publicKey': 'pk-sender',
                },
                {
                  'peerId': 'peer-rp004-added',
                  'role': 'writer',
                  'publicKey': 'pk-added',
                },
              ],
              'createdBy': 'peer-admin',
              'createdAt': initialGroupCreatedAt.toIso8601String(),
            },
          }),
        ),
        (
          name: 'members_added',
          text: jsonEncode({
            '__sys': 'members_added',
            'members': [
              {
                'peerId': 'peer-rp004-added-a',
                'username': 'Added A',
                'role': 'writer',
                'publicKey': 'pk-added-a',
              },
              {
                'peerId': 'peer-rp004-added-b',
                'username': 'Added B',
                'role': 'writer',
                'publicKey': 'pk-added-b',
              },
            ],
            'groupConfig': {
              'name': 'Test Group',
              'groupType': 'chat',
              'members': [
                {
                  'peerId': 'peer-admin',
                  'role': 'admin',
                  'publicKey': 'pk-admin',
                },
                {
                  'peerId': 'peer-sender',
                  'role': 'writer',
                  'publicKey': 'pk-sender',
                },
                {
                  'peerId': 'peer-rp004-added-a',
                  'role': 'writer',
                  'publicKey': 'pk-added-a',
                },
                {
                  'peerId': 'peer-rp004-added-b',
                  'role': 'writer',
                  'publicKey': 'pk-added-b',
                },
              ],
              'createdBy': 'peer-admin',
              'createdAt': initialGroupCreatedAt.toIso8601String(),
            },
          }),
        ),
        (
          name: 'member_removed',
          text: jsonEncode({
            '__sys': 'member_removed',
            'member': {'peerId': 'peer-admin', 'username': 'Admin'},
            'groupConfig': {
              'name': 'Test Group',
              'groupType': 'chat',
              'members': [
                {
                  'peerId': 'peer-sender',
                  'role': 'writer',
                  'publicKey': 'pk-sender',
                },
              ],
              'createdBy': 'peer-admin',
              'createdAt': initialGroupCreatedAt.toIso8601String(),
            },
          }),
        ),
        (
          name: 'member_role_updated',
          text: jsonEncode({
            '__sys': 'member_role_updated',
            'member': {
              'peerId': 'peer-admin',
              'username': 'Admin',
              'role': 'writer',
              'publicKey': 'pk-admin',
            },
            'groupConfig': {
              'name': 'Test Group',
              'groupType': 'chat',
              'members': [
                {
                  'peerId': 'peer-admin',
                  'role': 'writer',
                  'publicKey': 'pk-admin',
                },
                {
                  'peerId': 'peer-sender',
                  'role': 'writer',
                  'publicKey': 'pk-sender',
                },
              ],
              'createdBy': 'peer-admin',
              'createdAt': initialGroupCreatedAt.toIso8601String(),
            },
          }),
        ),
        (
          name: 'group_metadata_updated',
          text: jsonEncode({
            '__sys': 'group_metadata_updated',
            'updatedAt': '2026-04-05T12:45:00.000Z',
            'groupConfig': {
              'name': 'Unauthorized Name',
              'groupType': 'chat',
              'description': 'Unauthorized description',
              'metadataUpdatedAt': '2026-04-05T12:45:00.000Z',
              'members': [
                {
                  'peerId': 'peer-admin',
                  'role': 'admin',
                  'publicKey': 'pk-admin',
                },
                {
                  'peerId': 'peer-sender',
                  'role': 'writer',
                  'publicKey': 'pk-sender',
                },
              ],
              'createdBy': 'peer-admin',
              'createdAt': initialGroupCreatedAt.toIso8601String(),
            },
          }),
        ),
        (
          name: 'group_dissolved',
          text: jsonEncode({
            '__sys': 'group_dissolved',
            'dissolvedAt': '2026-04-05T12:50:00.000Z',
            'dissolvedBy': 'peer-sender',
          }),
        ),
      ];

      for (final mutationEvent in mutationEvents) {
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-sender',
          'senderUsername': 'Sender',
          'keyEpoch': 0,
          'text': mutationEvent.text,
          'timestamp': '2026-04-05T12:55:00.000Z',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final group = await groupRepo.getGroup('group-1');
        expect(group, isNotNull, reason: mutationEvent.name);
        expect(group!.name, 'Test Group', reason: mutationEvent.name);
        expect(group.description, isNull, reason: mutationEvent.name);
        expect(group.isDissolved, isFalse, reason: mutationEvent.name);
        expect(group.lastMetadataEventAt, isNull, reason: mutationEvent.name);

        final admin = await groupRepo.getMember('group-1', 'peer-admin');
        final sender = await groupRepo.getMember('group-1', 'peer-sender');
        expect(admin, isNotNull, reason: mutationEvent.name);
        expect(admin!.role, MemberRole.admin, reason: mutationEvent.name);
        expect(sender, isNotNull, reason: mutationEvent.name);
        expect(sender!.role, MemberRole.writer, reason: mutationEvent.name);
        expect(
          await groupRepo.getMember('group-1', 'peer-rp004-added'),
          isNull,
          reason: mutationEvent.name,
        );
        expect(
          await groupRepo.getMember('group-1', 'peer-rp004-added-a'),
          isNull,
          reason: mutationEvent.name,
        );
        expect(
          await groupRepo.getMember('group-1', 'peer-rp004-added-b'),
          isNull,
          reason: mutationEvent.name,
        );
        expect(msgRepo.count, 0, reason: mutationEvent.name);
        expect(bridge.commandLog, isEmpty, reason: mutationEvent.name);
      }
    },
  );

  test(
    'ML-013 removed peer injected membership and config snapshots leave state, bridge, and log unchanged',
    () async {
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        bridge: bridge,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start(sourceController.stream);

      final rejectedEvents = <({String name, String text})>[
        (
          name: 'member_added',
          text: jsonEncode({
            '__sys': 'member_added',
            'member': {
              'peerId': 'peer-ml013-added',
              'username': 'Added',
              'role': 'writer',
              'publicKey': 'pk-added',
            },
            'groupConfig': {
              'name': 'Test Group',
              'groupType': 'chat',
              'members': [
                {
                  'peerId': 'peer-admin',
                  'role': 'admin',
                  'publicKey': 'pk-admin',
                },
                {
                  'peerId': 'peer-sender',
                  'role': 'writer',
                  'publicKey': 'pk-sender',
                },
                {
                  'peerId': 'peer-ml013-added',
                  'role': 'writer',
                  'publicKey': 'pk-added',
                },
              ],
              'createdBy': 'peer-admin',
              'createdAt': initialGroupCreatedAt.toIso8601String(),
            },
          }),
        ),
        (
          name: 'members_added',
          text: jsonEncode({
            '__sys': 'members_added',
            'members': [
              {
                'peerId': 'peer-ml013-added-a',
                'username': 'Added A',
                'role': 'writer',
                'publicKey': 'pk-added-a',
              },
              {
                'peerId': 'peer-ml013-added-b',
                'username': 'Added B',
                'role': 'writer',
                'publicKey': 'pk-added-b',
              },
            ],
            'groupConfig': {
              'name': 'Test Group',
              'groupType': 'chat',
              'members': [
                {
                  'peerId': 'peer-admin',
                  'role': 'admin',
                  'publicKey': 'pk-admin',
                },
                {
                  'peerId': 'peer-sender',
                  'role': 'writer',
                  'publicKey': 'pk-sender',
                },
                {
                  'peerId': 'peer-ml013-added-a',
                  'role': 'writer',
                  'publicKey': 'pk-added-a',
                },
                {
                  'peerId': 'peer-ml013-added-b',
                  'role': 'writer',
                  'publicKey': 'pk-added-b',
                },
              ],
              'createdBy': 'peer-admin',
              'createdAt': initialGroupCreatedAt.toIso8601String(),
            },
          }),
        ),
        (
          name: 'member_removed',
          text: jsonEncode({
            '__sys': 'member_removed',
            'member': {'peerId': 'peer-admin', 'username': 'Admin'},
            'removedAt': '2026-04-05T12:45:00.000Z',
            'groupConfig': {
              'name': 'Test Group',
              'groupType': 'chat',
              'members': [
                {
                  'peerId': 'peer-sender',
                  'role': 'writer',
                  'publicKey': 'pk-sender',
                },
              ],
              'createdBy': 'peer-admin',
              'createdAt': initialGroupCreatedAt.toIso8601String(),
            },
          }),
        ),
        (
          name: 'member_role_updated',
          text: jsonEncode({
            '__sys': 'member_role_updated',
            'member': {
              'peerId': 'peer-sender',
              'username': 'Sender',
              'role': 'admin',
              'publicKey': 'pk-sender',
            },
            'groupConfig': {
              'name': 'Test Group',
              'groupType': 'chat',
              'members': [
                {
                  'peerId': 'peer-admin',
                  'role': 'admin',
                  'publicKey': 'pk-admin',
                },
                {
                  'peerId': 'peer-sender',
                  'role': 'admin',
                  'publicKey': 'pk-sender',
                },
              ],
              'createdBy': 'peer-admin',
              'createdAt': initialGroupCreatedAt.toIso8601String(),
            },
          }),
        ),
        (
          name: 'group_metadata_updated',
          text: jsonEncode({
            '__sys': 'group_metadata_updated',
            'updatedAt': '2026-04-05T12:49:00.000Z',
            'groupConfig': {
              'name': 'Removed Peer Name',
              'groupType': 'chat',
              'description': 'Removed peer metadata',
              'metadataUpdatedAt': '2026-04-05T12:49:00.000Z',
              'members': [
                {
                  'peerId': 'peer-admin',
                  'role': 'admin',
                  'publicKey': 'pk-admin',
                },
                {
                  'peerId': 'peer-sender',
                  'role': 'writer',
                  'publicKey': 'pk-sender',
                },
              ],
              'createdBy': 'peer-admin',
              'createdAt': initialGroupCreatedAt.toIso8601String(),
            },
          }),
        ),
      ];

      for (final rejectedEvent in rejectedEvents) {
        sourceController.add({
          'groupId': 'group-1',
          'senderId': 'peer-removed',
          'senderUsername': 'Removed',
          'keyEpoch': 0,
          'text': rejectedEvent.text,
          'timestamp': '2026-04-05T12:55:00.000Z',
        });

        await Future.delayed(const Duration(milliseconds: 50));

        final group = await groupRepo.getGroup('group-1');
        expect(group, isNotNull, reason: rejectedEvent.name);
        expect(group!.name, 'Test Group', reason: rejectedEvent.name);
        expect(group.description, isNull, reason: rejectedEvent.name);
        expect(group.lastMetadataEventAt, isNull, reason: rejectedEvent.name);

        final admin = await groupRepo.getMember('group-1', 'peer-admin');
        final sender = await groupRepo.getMember('group-1', 'peer-sender');
        expect(admin, isNotNull, reason: rejectedEvent.name);
        expect(admin!.role, MemberRole.admin, reason: rejectedEvent.name);
        expect(sender, isNotNull, reason: rejectedEvent.name);
        expect(sender!.role, MemberRole.writer, reason: rejectedEvent.name);
        expect(
          await groupRepo.getMember('group-1', 'peer-ml013-added'),
          isNull,
          reason: rejectedEvent.name,
        );
        expect(
          await groupRepo.getMember('group-1', 'peer-ml013-added-a'),
          isNull,
          reason: rejectedEvent.name,
        );
        expect(
          await groupRepo.getMember('group-1', 'peer-ml013-added-b'),
          isNull,
          reason: rejectedEvent.name,
        );
        expect(msgRepo.count, 0, reason: rejectedEvent.name);
        expect(eventLog.entries, isEmpty, reason: rejectedEvent.name);
        expect(
          bridge.commandLog,
          isNot(contains('group:updateConfig')),
          reason: rejectedEvent.name,
        );
      }
    },
  );
}
