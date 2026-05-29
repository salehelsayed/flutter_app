import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

String groupInviteStatusLabel(
  AppLocalizations l10n,
  GroupInviteDeliveryStatus status,
) {
  switch (status) {
    case GroupInviteDeliveryStatus.sent:
      return l10n.invite_status_sent;
    case GroupInviteDeliveryStatus.queued:
      return l10n.invite_status_queued;
    case GroupInviteDeliveryStatus.needsResend:
      return l10n.invite_status_needs_resend;
    case GroupInviteDeliveryStatus.cannotSend:
      return l10n.invite_status_cannot_send;
    case GroupInviteDeliveryStatus.joined:
      return l10n.invite_status_joined;
    case GroupInviteDeliveryStatus.unknown:
      return l10n.invite_status_unknown;
  }
}

String? groupInviteStatusDetail({
  required AppLocalizations l10n,
  required GroupInviteDeliveryStatus status,
  String? lastError,
}) {
  if (status != GroupInviteDeliveryStatus.cannotSend) {
    return null;
  }
  return groupInviteCannotSendReason(l10n, lastError);
}

String groupInviteCannotSendReason(AppLocalizations l10n, String? lastError) {
  switch (lastError) {
    case 'missing_secure_key':
      return l10n.invite_cannot_send_missing_secure_key_detail;
    case 'group_key_missing':
      return l10n.invite_cannot_send_group_key_missing_detail;
    case 'invalid_invite_payload':
      return l10n.invite_cannot_send_invalid_payload_detail;
    default:
      return l10n.invite_cannot_send_generic_detail;
  }
}

String groupInviteCannotSendSnackBarMessage(
  AppLocalizations l10n,
  String? lastError,
) {
  switch (lastError) {
    case 'missing_secure_key':
      return l10n.invite_cannot_send_missing_secure_key_snackbar;
    case 'group_key_missing':
      return l10n.invite_cannot_send_group_key_missing_snackbar;
    case 'invalid_invite_payload':
      return l10n.invite_cannot_send_invalid_payload_snackbar;
    default:
      return l10n.invite_cannot_send_generic_snackbar;
  }
}
