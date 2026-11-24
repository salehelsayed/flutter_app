import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/qr_code/application/contact_invite_link.dart';
import 'package:flutter_app/features/qr_code/application/parse_qr_payload_use_case.dart';

enum InviteContactSave { created, existing, stale }

enum ContactInviteRejection {
  invalid,
  expired,
  self,
  stale,
  blocked,
  keyMismatch,
  saveFailed,
}

typedef InviteRequestDelivery = ({
  SendContactRequestResult? sendResult,
  bool retryRetained,
});

/// Inserts only if the contact is still absent and `canCommit` allows it.
typedef SaveInviteContact =
    Future<InviteContactSave> Function(
      ContactModel verified, {
      required bool Function() canCommit,
    });

typedef LaunchInviteRequest =
    Future<InviteRequestDelivery> Function(
      ContactModel trusted, {
      required bool Function() canQueue,
      required Future<bool> Function() canTransmit,
    });

sealed class ContactInviteConfirmation {
  const ContactInviteConfirmation();
}

final class RejectedContactInvite extends ContactInviteConfirmation {
  const RejectedContactInvite(this.reason);

  final ContactInviteRejection reason;
}

final class SavedContactInvite extends ContactInviteConfirmation {
  const SavedContactInvite({
    required this.contact,
    required this.save,
    required this.delivery,
  });

  final ContactModel contact;
  final InviteContactSave save;
  final InviteRequestDelivery delivery;
}

/// Revalidates the original signed link before applying the user's consent.
Future<ContactInviteConfirmation> confirmContactInvite({
  required String link,
  required String ownPeerId,
  required bool Function() isAccountCurrent,
  required Bridge bridge,
  required Future<ContactModel?> Function(String peerId) loadContact,
  required SaveInviteContact saveIfAbsent,
  required LaunchInviteRequest launch,
  DateTime Function()? now,
}) async {
  if (!isAccountCurrent()) {
    return const RejectedContactInvite(ContactInviteRejection.stale);
  }
  final (result, invite) = await verifyContactInviteLink(
    link: link,
    bridge: bridge,
    ownPeerId: ownPeerId,
  );
  if (!isAccountCurrent()) {
    return const RejectedContactInvite(ContactInviteRejection.stale);
  }
  if (invite == null) {
    return RejectedContactInvite(switch (result) {
      ParseQRResult.expired => ContactInviteRejection.expired,
      ParseQRResult.selfScan => ContactInviteRejection.self,
      _ => ContactInviteRejection.invalid,
    });
  }

  final verified = invite.contact;
  final readTime = now ?? DateTime.now;
  ContactInviteRejection? actionRejection() {
    if (!isAccountCurrent()) return ContactInviteRejection.stale;
    if (readTime().isAfter(invite.expiresAt)) {
      return ContactInviteRejection.expired;
    }
    return null;
  }

  Future<(ContactModel?, ContactInviteRejection?)> readStoredContact() async {
    final beforeRead = actionRejection();
    if (beforeRead != null) return (null, beforeRead);
    final ContactModel? stored;
    try {
      stored = await loadContact(verified.peerId);
    } catch (_) {
      return (null, actionRejection() ?? ContactInviteRejection.saveFailed);
    }
    final afterRead = actionRejection();
    if (afterRead != null) return (null, afterRead);
    if (stored == null) return (null, null);
    if (stored.peerId != verified.peerId) {
      return (null, ContactInviteRejection.stale);
    }
    if (stored.isBlocked) return (null, ContactInviteRejection.blocked);
    if (stored.publicKey != verified.publicKey) {
      return (null, ContactInviteRejection.keyMismatch);
    }
    return (stored, null);
  }

  final (existing, lookupRejection) = await readStoredContact();
  final beforeSave = actionRejection() ?? lookupRejection;
  if (beforeSave != null) return RejectedContactInvite(beforeSave);
  var save = InviteContactSave.existing;
  if (existing == null) {
    try {
      save = await saveIfAbsent(
        verified,
        canCommit: () => actionRejection() == null,
      );
    } catch (_) {
      return RejectedContactInvite(
        actionRejection() ?? ContactInviteRejection.saveFailed,
      );
    }
    final afterSave = actionRejection();
    if (afterSave != null || save == InviteContactSave.stale) {
      return RejectedContactInvite(afterSave ?? ContactInviteRejection.stale);
    }
  }

  final (stored, storedRejection) = await readStoredContact();
  final beforeLaunch = actionRejection() ?? storedRejection;
  if (beforeLaunch != null || stored == null) {
    return RejectedContactInvite(beforeLaunch ?? ContactInviteRejection.stale);
  }

  ContactInviteRejection? guardRejection;
  bool canQueue() {
    guardRejection ??= actionRejection();
    return guardRejection == null;
  }

  Future<bool> canTransmit() async {
    if (!canQueue()) return false;
    final (current, rejection) = await readStoredContact();
    guardRejection ??= actionRejection() ?? rejection;
    if (current == null) guardRejection ??= ContactInviteRejection.stale;
    return guardRejection == null;
  }

  InviteRequestDelivery delivery;
  try {
    delivery = await launch(
      stored,
      canQueue: canQueue,
      canTransmit: canTransmit,
    );
  } catch (_) {
    delivery = (sendResult: null, retryRetained: false);
  }
  if (!isAccountCurrent()) {
    return const RejectedContactInvite(ContactInviteRejection.stale);
  }
  final denied = guardRejection;
  if (denied != null) return RejectedContactInvite(denied);
  // Expiry fences admission, so elapsed time during a send cannot hide its result.
  return SavedContactInvite(contact: stored, save: save, delivery: delivery);
}
