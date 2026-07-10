import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/application/resolve_introduction_notification_target_use_case.dart';

typedef ResolveIntroductionNotificationTargetFn =
    Future<IntroductionNotificationTargetResolution> Function(
      NotificationRouteTarget routeTarget,
    );
typedef OpenIntroAcceptConversationFn =
    Future<void> Function(ContactModel contact, DateTime? notificationTappedAt);
typedef OpenIntrosFallbackFn = Future<void> Function();

/// Shared open coordinator for the `_handleNotificationRouteTarget` Intros
/// case: remote (cold/background FCM tap) and local (warm mutual-accept tap)
/// notification opens both land here after the existing notification-open
/// preparation (which awaits the 1:1 inbox drain for Intros routes).
///
/// The resolver decides post-drain whether the local user is the introducer
/// of a canonical acceptance; only then is the tap redirected to the
/// recipient (User B) conversation — carrying the ORIGINAL tap timestamp —
/// otherwise every fallback keeps the existing Orbit/Intros route.
Future<void> openIntroAcceptNotificationRoute({
  required NotificationRouteTarget routeTarget,
  required DateTime? notificationTappedAt,
  required ResolveIntroductionNotificationTargetFn resolveTarget,
  required bool Function(NotificationRouteTarget conversationTarget)
  isConversationAlreadyActive,
  required OpenIntroAcceptConversationFn openConversation,
  required OpenIntrosFallbackFn openIntros,
}) async {
  IntroductionNotificationTargetResolution resolution;
  try {
    resolution = await resolveTarget(routeTarget);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'INTRO_ACCEPT_NOTIFICATION_RESOLVE_ERROR',
      details: {'error': e.toString()},
    );
    resolution = const IntroductionNotificationTargetResolution.intros(
      'resolver_error',
    );
  }

  final contact = resolution.contact;
  if (resolution.opensConversation && contact != null) {
    if (isConversationAlreadyActive(resolution.target)) {
      // Mirrors the conversation case's already-active guard: the mounted
      // screen self-refreshes on resume, so a second push would only stack a
      // duplicate route.
      emitFlowEvent(
        layer: 'FL',
        event: 'INTRO_ACCEPT_NOTIFICATION_ROUTE_ALREADY_ACTIVE',
        details: {'finalPeer': _shortPeer(contact.peerId)},
      );
      return;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'INTRO_ACCEPT_NOTIFICATION_CONVERSATION_REDIRECT',
      details: {
        'finalPeer': _shortPeer(contact.peerId),
        'statusContext': resolution.statusContext ?? '',
      },
    );
    await openConversation(contact, notificationTappedAt);
    return;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'INTRO_ACCEPT_NOTIFICATION_INTROS_FALLBACK',
    details: {'reason': resolution.reason},
  );
  await openIntros();
}

/// Flow events value-redact full bare peer IDs; a 12-char prefix stays
/// machine-matchable for the device-proof markers without leaking identity.
String _shortPeer(String peerId) {
  return peerId.length > 12 ? peerId.substring(0, 12) : peerId;
}
