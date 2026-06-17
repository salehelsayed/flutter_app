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

  /// Marks an admin-initiated revocation of this peer's pending invite.
  Future<void> markRevoked({
    required String groupId,
    required String peerId,
    DateTime? revokedAt,
  });

  /// Records that the invitee declined. Joined-wins: never downgrades an
  /// existing `joined` row (a decline-then-rejoin must stay `joined`).
  Future<void> markDeclined({
    required String groupId,
    required String peerId,
    DateTime? declinedAt,
  });

  Future<int> deleteAttempt({required String groupId, required String peerId});

  Future<int> deleteAttemptsForGroup(String groupId);
}
