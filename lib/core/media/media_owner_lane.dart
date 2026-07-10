/// 228: local owner-lane discriminator for `media_attachments` rows.
///
/// `messages.id` and `group_messages.id` are independent table-local primary
/// keys, so the same parent message ID can legally exist in BOTH lanes. Every
/// direct/group attachment write, read, delete, pending load, terminalization,
/// retry and cleanup seam must therefore carry an explicit owner — never infer
/// one from a parent-ID existence check (collisions are legal; existence
/// inference is migration-096-backfill-only).
///
/// Announcement conversations use [group] because their stored parents are
/// group messages; there is deliberately NO third lane.
///
/// The DB column `owner_lane` additionally allows `'unresolved'` for legacy
/// rows whose parent was ambiguous or absent at migration time. `unresolved`
/// is intentionally NOT an enum value: it is not a lane a caller may address —
/// such rows are excluded from every owner-scoped read and mutation.
enum MediaOwnerLane { direct, group }

/// The fail-closed legacy DB value (see migration 096).
const String kMediaOwnerLaneUnresolved = 'unresolved';

extension MediaOwnerLaneDbValue on MediaOwnerLane {
  /// The exact `owner_lane` column value ('direct' | 'group').
  String get dbValue => name;
}

/// Maps an `owner_lane` column value to a lane; `'unresolved'`, null and any
/// unknown value hydrate to null (no trusted owner).
MediaOwnerLane? mediaOwnerLaneFromDbValue(String? value) {
  switch (value) {
    case 'direct':
      return MediaOwnerLane.direct;
    case 'group':
      return MediaOwnerLane.group;
    default:
      return null;
  }
}

/// Thrown when a media attachment write would violate the immutable
/// `(attachmentId, ownerLane, messageId)` identity: a cross-owner or
/// cross-parent re-save, an attempt to adopt an `unresolved` legacy row, or
/// a model stamped with a different lane than the caller's typed owner.
///
/// The repository throws this BEFORE any secure-store/file/database side
/// effect; the DB save helper re-throws it inside the write transaction as
/// the final race guard.
class MediaAttachmentOwnerViolation implements Exception {
  MediaAttachmentOwnerViolation(this.message);

  final String message;

  @override
  String toString() => 'MediaAttachmentOwnerViolation: $message';
}
