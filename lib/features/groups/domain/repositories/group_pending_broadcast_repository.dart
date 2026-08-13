import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';

/// Durable queue of group system broadcasts that were persisted locally but
/// failed to leave the device, drained on the next rejoin/foreground.
abstract class GroupPendingBroadcastRepository {
  /// Idempotent: a broadcast sharing `(groupId, sourceMessageId)` is not
  /// duplicated.
  Future<void> enqueue(GroupPendingBroadcast broadcast);

  Future<List<GroupPendingBroadcast>> forGroup(String groupId);

  Future<List<GroupPendingBroadcast>> all();

  Future<int> countForGroup(String groupId);

  Future<void> remove(String id);

  /// Removes every obsolete broadcast owned by one committed left/dissolved
  /// group. The fallback remains strictly target-scoped.
  Future<void> removeForGroup(String groupId) async {
    final pending = await forGroup(groupId);
    for (final broadcast in pending) {
      await remove(broadcast.id);
    }
  }
}

abstract interface class GroupPendingBroadcastExactRepository {
  Future<bool> removeIfExact(GroupPendingBroadcast expected);
}

abstract interface class GroupPendingBroadcastProtectedRecipientRepository {
  Future<bool> removeRecipientIfExact(
    GroupPendingBroadcast expected,
    String recipientPeerId,
  );
}

abstract interface class GroupPendingBroadcastProtectedBatchRepository {
  Future<bool> enqueueProtectedBatch(List<GroupPendingBroadcast> rows);
}

Future<bool> removeGroupPendingBroadcastIfExact(
  GroupPendingBroadcastRepository repository,
  GroupPendingBroadcast expected,
) async {
  if (repository case final GroupPendingBroadcastExactRepository exact) {
    return exact.removeIfExact(expected);
  }
  final rows = await repository.forGroup(expected.groupId);
  GroupPendingBroadcast? current;
  for (final row in rows) {
    if (row.id == expected.id) {
      current = row;
      break;
    }
  }
  if (current == null || !sameExactGroupPendingBroadcast(current, expected)) {
    return false;
  }
  await repository.remove(expected.id);
  return true;
}
