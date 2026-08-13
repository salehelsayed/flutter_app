/// 362: the linked-device authority every production conversation route must
/// carry.
///
/// Before this existed, `directEventFanout`, `directDeviceTrust` and
/// `modalityGate` were supplied at exactly ONE of the six production
/// `ConversationWired` pushes (the notification-tap route), so ordinary
/// navigation from Feed, Orbit, Posts or the first-time experience opened a
/// chat with no fanout authority, no device-trust capability and the
/// allow-everything modality default. Bundling the three keeps every route a
/// single-field edit and puts the linked-runtime gate expression in one place
/// instead of copying it per site.
library;

import 'package:flutter_app/features/contacts/application/direct_contact_device_trust.dart';
import 'package:flutter_app/features/conversation/application/direct_event_fanout_coordinator.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_conversation_modality_gate.dart';
import 'package:flutter_app/core/config/direct_linked_event_fanout_flag.dart';
import 'package:flutter_app/core/config/direct_linked_media_fanout_flag.dart';
import 'package:flutter_app/core/config/direct_media_blob_custody_client_flag.dart';

/// Threaded from the composition root down every shell that can push a 1:1
/// conversation. A null instance means "no linked authority in this
/// composition" and preserves the incumbent single-target behaviour exactly.
class DirectConversationRouteAuthority {
  const DirectConversationRouteAuthority({
    this.directEventFanoutResolver,
    this.directDeviceTrust,
    this.isLinkedBlobFreeRuntime,
  });

  /// Builds the shared blob-free fanout authoring owner for the CURRENT
  /// role/identity at route-push time; a null result means incumbent sender.
  final DirectEventFanoutAuthoring? Function()? directEventFanoutResolver;

  /// Plan 360 linked-device admission/verification capability. Without it the
  /// contact profile hands out an inert `Unavailable` capability and the QR
  /// pairing scan silently no-ops.
  final DirectContactDeviceTrustCapability? directDeviceTrust;

  /// True while this process runs the restricted linked blob-free role.
  final bool Function()? isLinkedBlobFreeRuntime;

  /// Resolved at push time, never cached: the owner is identity-scoped.
  DirectEventFanoutAuthoring? get directEventFanout =>
      directEventFanoutResolver?.call();

  /// A linked secondary regains the media/voice/private composer ONLY when the
  /// full linked-media authoring triple is compiled on; otherwise the 361
  /// blob-free surface stays byte-exact. The primary role always allows
  /// everything, which is the incumbent default.
  DirectConversationModalityGate get modalityGate {
    if (!(isLinkedBlobFreeRuntime?.call() ?? false)) {
      return const DirectConversationModalityGate();
    }
    return (kDirectLinkedMediaFanoutEnabled &&
            kDirectMediaBlobCustodyClientEnabled &&
            kDirectLinkedEventFanoutEnabled)
        ? const DirectConversationModalityGate()
        : const DirectConversationModalityGate.linkedBlobFree();
  }
}

/// Null-safe accessors so a route that has no authority reads exactly like the
/// incumbent construction sites did.
extension DirectConversationRouteAuthorityResolution
    on DirectConversationRouteAuthority? {
  DirectEventFanoutAuthoring? get resolvedDirectEventFanout =>
      this?.directEventFanout;

  DirectContactDeviceTrustCapability? get resolvedDirectDeviceTrust =>
      this?.directDeviceTrust;

  DirectConversationModalityGate get resolvedModalityGate =>
      this?.modalityGate ?? const DirectConversationModalityGate();
}
