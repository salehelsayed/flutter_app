import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_repair.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  test(
    'live decrypt repair without replay envelope records waiting attempt and stays pending',
    () async {
      final bridge = FakeBridge();
      final groupRepo = InMemoryGroupRepository();
      final msgRepo = InMemoryGroupMessageRepository();
      final pendingRepo = _InMemoryGroupPendingKeyRepairRepository();
      final now = DateTime.utc(2026, 5, 24, 12);
      final repairId = liveGroupPendingKeyRepairId(
        groupId: 'group-1',
        senderPeerId: 'peer-sender',
        keyEpoch: 2,
        localKeyEpoch: 1,
      );

      await pendingRepo.upsertPendingRepair(
        GroupPendingKeyRepair(
          id: repairId,
          groupId: 'group-1',
          messageId: repairId,
          senderPeerId: 'peer-sender',
          transportPeerId: 'peer-sender',
          payloadType: groupOfflineReplayPayloadTypeMessage,
          keyEpoch: 2,
          replayEnvelopeJson: null,
          status: groupPendingKeyRepairStatusPendingKey,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await msgRepo.saveMessage(
        GroupMessage(
          id: repairId,
          groupId: 'group-1',
          senderPeerId: 'peer-sender',
          transportPeerId: 'peer-sender',
          senderUsername: null,
          text: groupPendingKeyRepairPlaceholderText,
          timestamp: now,
          keyGeneration: 2,
          status: groupPendingKeyRepairStatusPendingKey,
          isIncoming: true,
          createdAt: now,
        ),
      );

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

      expect(repairedCount, 0);
      final repair = await pendingRepo.getRepair(repairId);
      expect(repair, isNotNull);
      expect(repair!.status, groupPendingKeyRepairStatusPendingKey);
      expect(repair.finalizedAt, isNull);
      expect(repair.attempts, 1);
      expect(repair.lastError, 'waiting for replay envelope');

      final placeholder = await msgRepo.getMessage(repairId);
      expect(placeholder, isNotNull);
      expect(placeholder!.status, groupPendingKeyRepairStatusPendingKey);
      expect(placeholder.text, groupPendingKeyRepairPlaceholderText);
      expect(bridge.commandLog, isNot(contains('group.decrypt')));
    },
  );
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
