import '../models/group_invite_consumption.dart';
import '../models/group_invite_revocation.dart';
import '../models/pending_group_invite.dart';

abstract class PendingGroupInviteRepository {
  Future<void> savePendingInvite(PendingGroupInvite invite);

  Future<void> saveRevokedInvite(GroupInviteRevocation revocation);

  Future<void> saveConsumedInvite(GroupInviteConsumption consumption);

  Future<List<PendingGroupInvite>> getPendingInvites();

  Future<PendingGroupInvite?> getPendingInvite(String groupId);

  Future<GroupInviteRevocation?> getRevokedInvite(String inviteId);

  Future<GroupInviteConsumption?> getConsumedInvite(String inviteId);

  Future<void> deletePendingInvite(String groupId);

  Future<int> deleteExpiredPendingInvites(DateTime now);

  Future<int> deleteExpiredRevokedInvites(DateTime now);

  Future<int> deleteExpiredConsumedInvites(DateTime now);
}
