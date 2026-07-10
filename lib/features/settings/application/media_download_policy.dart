import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/settings/domain/models/media_download_preferences.dart';

/// 229: pure, side-effect-free decision for whether a received media
/// attachment may be transferred right now.
///
/// Every AUTOMATIC transfer entry point (direct listener, direct mounted /
/// staged-drain / older-page recovery, shared group loader) consults this
/// immediately before calling the download use case. Explicit user retries
/// pass [shouldAutoDownload]'s `userInitiated: true`, which bypasses only the
/// auto preference — never owner resolution, protection or the integrity
/// quarantine.
class MediaDownloadPolicy {
  const MediaDownloadPolicy._();

  /// Decides one transfer. Throws before deciding when the storage owner is
  /// untrusted or contradicts the product kind:
  ///
  /// - [storageOwner] null (an `unresolved` legacy row) throws
  ///   [MediaAttachmentOwnerViolation] — such rows are not addressable.
  /// - [MediaConversationKind.oneToOne] requires [MediaOwnerLane.direct];
  ///   discussions AND announcements require [MediaOwnerLane.group]
  ///   (announcement is a product kind, never a third storage owner).
  static bool shouldAutoDownload({
    required MediaDownloadPreferences preferences,
    required MediaConversationKind conversationKind,
    required MediaOwnerLane? storageOwner,
    required String mediaType,
    required MediaDownloadNetwork network,
    String downloadStatus = kMediaDownloadStatusPending,
    bool userInitiated = false,
    bool isProtected = false,
  }) {
    if (storageOwner == null) {
      throw MediaAttachmentOwnerViolation(
        'download policy consulted for an unresolved owner lane',
      );
    }
    final expectedOwner = conversationKind == MediaConversationKind.oneToOne
        ? MediaOwnerLane.direct
        : MediaOwnerLane.group;
    if (storageOwner != expectedOwner) {
      throw ArgumentError(
        '$conversationKind media must be ${expectedOwner.dbValue}-owned, '
        'got ${storageOwner.dbValue}',
      );
    }

    // Protection and the tamper quarantine are never bypassed, manual or not.
    if (isProtected) return false;
    if (downloadStatus == kMediaDownloadStatusIntegrityFailed) return false;

    // Completed and outgoing states carry nothing for a received-media
    // download to do.
    switch (downloadStatus) {
      case kMediaDownloadStatusDone:
      case kMediaDownloadStatusUploadPending:
      case kMediaDownloadStatusUploadFailed:
      case kMediaDownloadStatusUploadCancelled:
        return false;
    }

    // A user-removed local copy never re-downloads automatically; only the
    // explicit retry affordance may transfer it again.
    if (downloadStatus == kMediaDownloadStatusEvicted) return userInitiated;

    // Manual action bypasses only the auto preference (including terminal
    // relay unavailability, which settles truthfully again).
    if (userInitiated) return true;

    // Terminal states are never automatic work.
    if (downloadStatus == kMediaDownloadStatusDownloadFailed) return false;

    return preferences.isAutoDownloadEnabled(
      kind: conversationKind,
      mediaType: mediaType,
      network: network,
    );
  }
}

/// One injectable policy/network decision capability shared by every
/// automatic transfer entry point. Implementations resolve the current
/// preferences and network class and delegate to [MediaDownloadPolicy].
///
/// A null decider on a seam means "no user policy installed" and preserves
/// HEAD behavior (transfer allowed), so existing callers and tests stay
/// unchanged until production wiring passes a real decider.
abstract class MediaAutoDownloadDecider {
  Future<bool> shouldAutoDownload({
    required MediaConversationKind conversationKind,
    required MediaOwnerLane? storageOwner,
    required String mediaType,
    required String downloadStatus,
    bool userInitiated = false,
    bool isProtected = false,
  });
}

/// Process-wide default decider consulted when a seam's constructor-injected
/// decider is null. `main.dart` installs the preference-backed decider once
/// at startup so EVERY automatic transfer entry point is gated without
/// threading the dependency through every intermediate widget; tests leave
/// this unset (HEAD-compatible allow) and inject per-widget deciders.
MediaAutoDownloadDecider? defaultMediaAutoDownloadDecider;
