/// 230: typed, callback-only description of a single page in the shared media
/// viewer.
///
/// The shared viewer is deliberately transport-free: it NEVER imports a
/// [P2PService], bridge, relay, send/delete use case, or a message repository.
/// The lane owner (plans 231-242) constructs each [MediaViewerItem] with an
/// explicit [MediaOwnerLane], the capabilities it authorizes, and the local
/// protection/availability state. The viewer renders only what it is handed and
/// invokes a supplied callback with the exact current item; it never infers
/// lane, role, direction, view-once state, or authorization from a path or MIME.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';

/// What kind of media a viewer page shows. Supplied by the lane owner — never
/// inferred from the path/extension inside the shared viewer.
enum MediaViewerKind { image, gif, video }

/// A per-item action the viewer may surface. The viewer performs no side
/// effect itself: it invokes the supplied [MediaViewerActionCallback] with the
/// exact current item. Concrete per-lane policies live in plans 231-242.
enum MediaViewerAction { save, share, forward, delete, bookmark }

/// The settled outcome of an awaited [MediaViewerActionCallback].
enum MediaViewerActionStatus { success, cancelled, failure }

/// Immutable result of one action dispatch. The viewer awaits the callback
/// exactly once and surfaces this truthfully; it never pops the route or
/// mutates a chat optimistically on [MediaViewerActionStatus.failure].
@immutable
class MediaViewerActionResult {
  const MediaViewerActionResult(this.status, {this.message});

  final MediaViewerActionStatus status;
  final String? message;

  bool get isSuccess => status == MediaViewerActionStatus.success;
  bool get isCancelled => status == MediaViewerActionStatus.cancelled;
  bool get isFailure => status == MediaViewerActionStatus.failure;

  static const MediaViewerActionResult success = MediaViewerActionResult(
    MediaViewerActionStatus.success,
  );
  static const MediaViewerActionResult cancelled = MediaViewerActionResult(
    MediaViewerActionStatus.cancelled,
  );
  static const MediaViewerActionResult failure = MediaViewerActionResult(
    MediaViewerActionStatus.failure,
  );
}

/// Local protection / availability state for a single item, supplied by the
/// lane owner. The viewer NEVER derives these from a path, MIME, or string.
@immutable
class MediaViewerProtection {
  const MediaViewerProtection({
    this.isDownloaded = true,
    this.isIntegrityVerified = true,
    this.isProtected = false,
  });

  /// The bytes are present locally.
  final bool isDownloaded;

  /// The bytes passed the lane's integrity check.
  final bool isIntegrityVerified;

  /// The item is locally protected (e.g. a consumed view-once or a locked
  /// item) and no action may run against it.
  final bool isProtected;

  /// Fail-closed availability: actions may only run against downloaded,
  /// integrity-verified, unprotected items.
  bool get isAvailable => isDownloaded && isIntegrityVerified && !isProtected;
}

/// The exact set of actions the lane owner authorizes for one item. The viewer
/// renders only these and treats everything else as absent. Ownership and
/// availability are additional fail-closed gates on top of this set.
@immutable
class MediaViewerActionCapabilities {
  const MediaViewerActionCapabilities({
    this.allowed = const <MediaViewerAction>{},
  });

  final Set<MediaViewerAction> allowed;

  bool allows(MediaViewerAction action) => allowed.contains(action);

  static const MediaViewerActionCapabilities none =
      MediaViewerActionCapabilities();
}

/// Immutable, typed identity + metadata for one viewer page.
///
/// Carries stable attachment/message IDs, an explicit [owner] lane (null only
/// for legacy path-only pages, which are action- and resume-ineligible), the
/// local path, MIME, byte size, image dimensions or video duration, caption,
/// sender label, timestamp, download/integrity availability, local protection,
/// and the authorized action capabilities.
@immutable
class MediaViewerItem {
  const MediaViewerItem({
    required this.attachmentId,
    required this.messageId,
    required this.kind,
    required this.mime,
    this.owner,
    this.localPath,
    this.sizeBytes,
    this.width,
    this.height,
    this.durationMs,
    this.caption,
    this.senderLabel,
    this.timestamp,
    this.protection = const MediaViewerProtection(),
    this.capabilities = MediaViewerActionCapabilities.none,
  });

  /// Stable relay-blob / attachment ID. Used as the durable resume key with
  /// [owner]; never a path.
  final String attachmentId;

  /// Stable parent message ID (table-local; only meaningful with [owner]).
  final String messageId;

  final MediaViewerKind kind;
  final String mime;

  /// Explicit lane. Null means a legacy path-only page with no trusted owner —
  /// such items are action- and resume-ineligible and fail closed.
  final MediaOwnerLane? owner;

  final String? localPath;
  final int? sizeBytes;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? caption;
  final String? senderLabel;
  final DateTime? timestamp;
  final MediaViewerProtection protection;
  final MediaViewerActionCapabilities capabilities;

  bool get isVideo => kind == MediaViewerKind.video;

  /// True only when a trusted lane owner is attached.
  bool get hasOwner => owner != null;

  /// A video with a trusted owner: the only shape eligible for durable resume
  /// persistence. Non-video, ownerless, and unresolved items never read or
  /// write resume state.
  bool get isResumable => isVideo && hasOwner;

  /// Fail-closed gate shared by every action: a trusted owner AND local
  /// availability (downloaded, integrity-verified, unprotected).
  bool get isActionEligible => hasOwner && protection.isAvailable;

  /// Whether [action] may be dispatched for this item: eligible AND the lane
  /// owner authorized this capability.
  bool canDispatch(MediaViewerAction action) =>
      isActionEligible && capabilities.allows(action);

  /// Diagnostic string. Intentionally includes caption/path/sender so that any
  /// accidental `emit(item.toString())` is caught by the boundary/redaction
  /// test (TC-230-08). Production diagnostics emit only redacted IDs/outcomes,
  /// never this value.
  @override
  String toString() =>
      'MediaViewerItem(attachmentId: $attachmentId, messageId: $messageId, '
      'kind: $kind, owner: ${owner?.dbValue}, mime: $mime, '
      'caption: $caption, senderLabel: $senderLabel, localPath: $localPath)';
}

/// Callback invoked with the exact current item + action. Returns a settled
/// [MediaViewerActionResult]; the viewer awaits it once and never pops or
/// mutates a chat optimistically on failure.
typedef MediaViewerActionCallback =
    Future<MediaViewerActionResult> Function(
      MediaViewerItem item,
      MediaViewerAction action,
    );
