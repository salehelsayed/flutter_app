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
}
