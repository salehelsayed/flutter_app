import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';

String groupInviteStatusLabel(GroupInviteDeliveryStatus status) {
  switch (status) {
    case GroupInviteDeliveryStatus.sent:
      return 'Invite sent';
    case GroupInviteDeliveryStatus.queued:
      return 'In their inbox';
    case GroupInviteDeliveryStatus.needsResend:
      return 'Resend needed';
    case GroupInviteDeliveryStatus.cannotSend:
      return 'Cannot send';
    case GroupInviteDeliveryStatus.joined:
      return 'Joined';
    case GroupInviteDeliveryStatus.unknown:
      return 'Invite unknown';
  }
}

String? groupInviteStatusDetail({
  required GroupInviteDeliveryStatus status,
  String? lastError,
}) {
  if (status != GroupInviteDeliveryStatus.cannotSend) {
    return null;
  }
  return groupInviteCannotSendReason(lastError);
}

String groupInviteCannotSendReason(String? lastError) {
  switch (lastError) {
    case 'missing_secure_key':
      return "We don't have the secure info needed to invite this friend. Ask them to open or reinstall the app, then try again.";
    case 'group_key_missing':
      return 'This group is missing the secure invite key. Reopen the app and try again.';
    case 'invalid_invite_payload':
      return 'This invite could not be prepared. Reopen the app and try again.';
    default:
      return 'We could not prepare a secure invite for this friend. They may need to open or reinstall the app before you can invite them.';
  }
}

String groupInviteCannotSendSnackBarMessage(String? lastError) {
  switch (lastError) {
    case 'missing_secure_key':
      return "Cannot send: we don't have the secure info needed to invite this friend.";
    case 'group_key_missing':
      return 'Cannot send: this group is missing the secure invite key.';
    case 'invalid_invite_payload':
      return 'Cannot send: this invite could not be prepared.';
    default:
      return 'Cannot send: we could not prepare a secure invite for this friend.';
  }
}
