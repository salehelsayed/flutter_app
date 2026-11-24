import 'package:flutter_app/features/qr_code/application/build_qr_payload_use_case.dart';
import 'package:flutter_app/features/qr_code/application/contact_invite_link.dart';

enum ContactInviteShareResult { presented, unavailable, failed }

// Turn on only after an installed Play and TestFlight build each prove re-tap.
bool get contactInviteSharingEnabled => false;

Future<ContactInviteShareResult> shareContactInvite({
  required bool Function() isCurrent,
  required Future<(BuildQRPayloadResult, String?)> Function() buildQr,
  required Future<bool> Function(String link) present,
}) async {
  if (!isCurrent()) return ContactInviteShareResult.unavailable;
  try {
    final (status, signedQr) = await buildQr();
    if (!isCurrent()) return ContactInviteShareResult.unavailable;
    if (status != BuildQRPayloadResult.success || signedQr == null) {
      return ContactInviteShareResult.failed;
    }
    final link = buildContactInviteLink(signedQr);
    if (link == null) return ContactInviteShareResult.failed;
    return await present(link)
        ? ContactInviteShareResult.presented
        : ContactInviteShareResult.failed;
  } catch (_) {
    return ContactInviteShareResult.failed;
  }
}
