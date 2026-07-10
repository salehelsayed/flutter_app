import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';

/// Outcome of resolving an anchored Intros notification target after the
/// notification-open inbox drain.
///
/// Either the local user is the introducer of a canonical `accept` and the
/// recipient (User B) still resolves as a contact — in which case [target] is
/// B's conversation and [contact] is non-null — or the resolution fails
/// closed to the original generic Intros route.
class IntroductionNotificationTargetResolution {
  final NotificationRouteTarget target;
  final ContactModel? contact;
  final String reason;

  /// Machine-readable acceptance progress for the resolved introduction:
  /// `b_accept_recorded` while the intro is still pending the second
  /// response, `bc_connected` once mutually accepted. Null on fallback.
  final String? statusContext;

  const IntroductionNotificationTargetResolution._({
    required this.target,
    this.contact,
    required this.reason,
    this.statusContext,
  });

  const IntroductionNotificationTargetResolution.intros(String reason)
    : this._(target: const NotificationRouteTarget.intros(), reason: reason);

  IntroductionNotificationTargetResolution.conversation({
    required ContactModel contact,
    required String statusContext,
  }) : this._(
         target: NotificationRouteTarget.conversation(contact.peerId),
         contact: contact,
         reason: 'introducer_accept',
         statusContext: statusContext,
       );

  bool get opensConversation =>
      target.kind == NotificationRouteTargetKind.conversation &&
      contact != null;
}

/// Resolves an Intros notification target to the introducer's originating
/// recipient conversation, or fails closed to the generic Intros route.
///
/// May return B's conversation ONLY when all of these hold after the
/// notification-open drain:
/// - the target carries a canonical `accept` envelope message ID,
/// - the introduction row exists locally,
/// - the local identity is the introduction's introducer, and
/// - the recipient (User B) still resolves as a contact.
///
/// The route is always the introduction `recipientId` (User B) — never the
/// responder — so B-accept and C-accept for the same introduction both land
/// in the thread that carries the introduction status messages.
Future<IntroductionNotificationTargetResolution>
resolveIntroductionNotificationTarget({
  required NotificationRouteTarget routeTarget,
  required IntroductionRepository introRepo,
  required ContactRepository contactRepo,
  required Future<String?> Function() loadOwnPeerId,
}) async {
  if (routeTarget.kind != NotificationRouteTargetKind.intros) {
    return const IntroductionNotificationTargetResolution.intros(
      'not_intros_route',
    );
  }

  final identity = IntroductionPayload.parseEnvelopeMessageId(
    routeTarget.messageId,
  );
  if (identity == null) {
    return const IntroductionNotificationTargetResolution.intros(
      'unanchored_or_malformed_message_id',
    );
  }
  if (identity.action != 'accept') {
    return const IntroductionNotificationTargetResolution.intros(
      'not_accept_action',
    );
  }

  final intro = await introRepo.getIntroduction(identity.introductionId);
  if (intro == null) {
    return const IntroductionNotificationTargetResolution.intros(
      'introduction_missing',
    );
  }

  final ownPeerId = await loadOwnPeerId();
  if (ownPeerId == null || ownPeerId != intro.introducerId) {
    return const IntroductionNotificationTargetResolution.intros(
      'not_introducer',
    );
  }

  final contact = await contactRepo.getContact(intro.recipientId);
  if (contact == null) {
    return const IntroductionNotificationTargetResolution.intros(
      'recipient_contact_missing',
    );
  }

  return IntroductionNotificationTargetResolution.conversation(
    contact: contact,
    statusContext: intro.status == IntroductionOverallStatus.mutualAccepted
        ? 'bc_connected'
        : 'b_accept_recorded',
  );
}
