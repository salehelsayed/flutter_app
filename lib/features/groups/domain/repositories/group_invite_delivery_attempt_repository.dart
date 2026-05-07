import '../models/group_invite_delivery_attempt.dart';

abstract class GroupInviteDeliveryAttemptRepository {
  Future<void> saveAttempt(GroupInviteDeliveryAttempt attempt);

  Future<GroupInviteDeliveryAttempt?> getAttempt({
    required String groupId,
    required String peerId,
  });

  Future<List<GroupInviteDeliveryAttempt>> getAttemptsForGroup(String groupId);

  Future<GroupInviteDeliveryStatus> getStatusForMember({
    required String groupId,
    required String peerId,
  });

  Future<Map<String, GroupInviteDeliveryStatus>> getStatusesForGroupMembers(
    String groupId,
  );

  Future<void> updateStatus({
    required String groupId,
    required String peerId,
    required GroupInviteDeliveryStatus status,
    DateTime? updatedAt,
  });

  Future<void> markJoined({
    required String groupId,
    required String peerId,
    String? username,
    DateTime? joinedAt,
  });

  Future<int> deleteAttempt({required String groupId, required String peerId});

  Future<int> deleteAttemptsForGroup(String groupId);
}
