import '../models/group_history_gap_repair.dart';

class GroupHistoryGapRepairUpsertResult {
  final GroupHistoryGapRepair repair;
  final bool created;

  const GroupHistoryGapRepairUpsertResult({
    required this.repair,
    required this.created,
  });
}

abstract class GroupHistoryGapRepairRepository {
  Future<GroupHistoryGapRepairUpsertResult> upsertDetected(
    GroupHistoryGapRepair repair,
  );

  Future<GroupHistoryGapRepair?> getRepair({
    required String groupId,
    required String gapId,
  });

  Future<GroupHistoryGapRepair?> getLatestRepairForGroup(String groupId);

  Future<List<GroupHistoryGapRepair>> getVisibleRepairsForGroup(
    String groupId, {
    int limit = 20,
  });

  Future<void> markRepairing({required String groupId, required String gapId});

  Future<void> recordAttempt({
    required String groupId,
    required String gapId,
    required String sourcePeerId,
    required String? lastError,
  });

  Future<void> markRepaired({
    required String groupId,
    required String gapId,
    required List<String> repairedMessageIds,
  });

  Future<void> markFailed({
    required String groupId,
    required String gapId,
    required String reason,
  });
}

abstract interface class GroupHistoryGapRepairExactRepository {
  Future<bool> replaceIfExact({
    required GroupHistoryGapRepair expected,
    required GroupHistoryGapRepair replacement,
  });
}

Future<bool> replaceGroupHistoryGapRepairIfExact(
  GroupHistoryGapRepairRepository repository, {
  required GroupHistoryGapRepair expected,
  required GroupHistoryGapRepair replacement,
}) async {
  if (repository case final GroupHistoryGapRepairExactRepository exact) {
    return exact.replaceIfExact(expected: expected, replacement: replacement);
  }
  final current = await repository.getRepair(
    groupId: expected.groupId,
    gapId: expected.gapId,
  );
  if (current == null ||
      !sameExactGroupHistoryGapRepair(current, expected) ||
      replacement.groupId != expected.groupId ||
      replacement.gapId != expected.gapId) {
    return false;
  }
  if (replacement.status == groupHistoryGapRepairStatusRepaired) {
    await repository.markRepaired(
      groupId: replacement.groupId,
      gapId: replacement.gapId,
      repairedMessageIds: replacement.repairedMessageIds,
    );
  } else if (replacement.status == groupHistoryGapRepairStatusFailed) {
    await repository.markFailed(
      groupId: replacement.groupId,
      gapId: replacement.gapId,
      reason: replacement.failureReason ?? 'failed',
    );
  } else if (replacement.attemptedSourcePeerIds.length >
      expected.attemptedSourcePeerIds.length) {
    String? added;
    for (final peerId in replacement.attemptedSourcePeerIds) {
      if (!expected.attemptedSourcePeerIds.contains(peerId)) {
        added = peerId;
        break;
      }
    }
    if (added == null) return false;
    await repository.recordAttempt(
      groupId: replacement.groupId,
      gapId: replacement.gapId,
      sourcePeerId: added,
      lastError: replacement.failureReason,
    );
  } else {
    await repository.markRepairing(
      groupId: replacement.groupId,
      gapId: replacement.gapId,
    );
  }
  return true;
}
