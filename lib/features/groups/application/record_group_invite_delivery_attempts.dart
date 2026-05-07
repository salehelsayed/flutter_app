import 'package:flutter_app/features/groups/application/send_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';

GroupInviteDeliveryStatus groupInviteDeliveryStatusForSendResult(
  SendGroupInviteResult result,
) {
  switch (result) {
    case SendGroupInviteResult.success:
      return GroupInviteDeliveryStatus.sent;
    case SendGroupInviteResult.queued:
      return GroupInviteDeliveryStatus.queued;
    case SendGroupInviteResult.nodeNotRunning:
    case SendGroupInviteResult.sendFailed:
      return GroupInviteDeliveryStatus.needsResend;
    case SendGroupInviteResult.encryptionRequired:
    case SendGroupInviteResult.invalidPayload:
      return GroupInviteDeliveryStatus.cannotSend;
  }
}

String? groupInviteDeliveryErrorForSendResult(SendGroupInviteResult result) {
  switch (result) {
    case SendGroupInviteResult.success:
    case SendGroupInviteResult.queued:
      return null;
    case SendGroupInviteResult.nodeNotRunning:
      return 'node_not_running';
    case SendGroupInviteResult.encryptionRequired:
      return 'missing_secure_key';
    case SendGroupInviteResult.invalidPayload:
      return 'invalid_invite_payload';
    case SendGroupInviteResult.sendFailed:
      return 'send_failed';
  }
}

Future<void> recordGroupInviteDeliveryBatch({
  required GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  required String groupId,
  required Iterable<GroupInviteAttempt> attempts,
  DateTime? now,
}) async {
  final repo = inviteDeliveryAttemptRepo;
  if (repo == null) return;
  final timestamp = (now ?? DateTime.now()).toUtc();

  for (final attempt in attempts) {
    await repo.saveAttempt(
      GroupInviteDeliveryAttempt(
        groupId: groupId,
        peerId: attempt.peerId,
        username: attempt.username,
        status: groupInviteDeliveryStatusForSendResult(attempt.result),
        attemptedAt: timestamp,
        updatedAt: timestamp,
        lastError: groupInviteDeliveryErrorForSendResult(attempt.result),
      ),
    );
  }
}

Future<void> recordMissingGroupKeyInviteDeliveryAttempts({
  required GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  required String groupId,
  required Iterable<GroupMember> members,
  DateTime? now,
}) async {
  final repo = inviteDeliveryAttemptRepo;
  if (repo == null) return;
  final timestamp = (now ?? DateTime.now()).toUtc();

  for (final member in members) {
    await repo.saveAttempt(
      GroupInviteDeliveryAttempt(
        groupId: groupId,
        peerId: member.peerId,
        username: member.username,
        status: GroupInviteDeliveryStatus.needsResend,
        attemptedAt: timestamp,
        updatedAt: timestamp,
        lastError: 'group_key_missing',
      ),
    );
  }
}
