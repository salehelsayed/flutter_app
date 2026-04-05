import '../models/pending_group_invite.dart';

abstract class PendingGroupInviteRepository {
  Future<void> savePendingInvite(PendingGroupInvite invite);

  Future<List<PendingGroupInvite>> getPendingInvites();

  Future<PendingGroupInvite?> getPendingInvite(String groupId);

  Future<void> deletePendingInvite(String groupId);

  Future<int> deleteExpiredPendingInvites(DateTime now);
}
