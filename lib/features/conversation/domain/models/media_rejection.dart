import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';

/// A single pre-send composer attachment that failed a size/GIF SEND policy,
/// addressed by its [index] in the pending-attachment list. [reason] is
/// normalized to the per-chip taxonomy: `too_large` | `gif_too_large` (149).
class MediaRejection {
  final int index;
  final String reason;

  const MediaRejection({required this.index, required this.reason});

  @override
  bool operator ==(Object other) =>
      other is MediaRejection && other.index == index && other.reason == reason;

  @override
  int get hashCode => Object.hash(index, reason);

  @override
  String toString() => 'MediaRejection(index: $index, reason: $reason)';
}

/// Normalizes a [GroupMediaSizePolicy] size/GIF rejection reason to the per-chip
/// taxonomy. The dedicated GIF cap reports `gif_size_exceeded`; every other
/// per-type cap (image/video/voice/file) and the degenerate-size reasons
/// collapse to the generic `too_large`.
String normalizeMediaRejectionReason(String? reason) =>
    reason == 'gif_size_exceeded' ? 'gif_too_large' : 'too_large';

/// Pure, side-effect-free SEND-size gate shared by the 1:1 and group composers.
///
/// Iterates [media] element-by-element so the failing INDEX is captured — the
/// group path no longer delegates to [GroupMediaSizePolicy.validateAttachments]
/// (which discards the index) — validating each attachment's final budget bytes
/// against its per-type cap. Returns one [MediaRejection] per failing index with
/// a normalized reason; empty when every attachment is within its cap. It emits
/// no snackbar (the inline chip carries the reason) and never short-circuits on
/// the first failure (every offending index is marked).
List<MediaRejection> collectPendingMediaSizeRejections(
  List<PendingComposerMedia> media,
  String? Function(String path) mimeResolver,
) {
  final rejections = <MediaRejection>[];
  for (var index = 0; index < media.length; index++) {
    final pending = media[index];
    final validation = GroupMediaSizePolicy.validateSize(
      sizeBytes: pending.budgetBytes,
      mime: mimeResolver(pending.file.path),
    );
    if (validation.isValid) continue;
    rejections.add(
      MediaRejection(
        index: index,
        reason: normalizeMediaRejectionReason(validation.reason),
      ),
    );
  }
  return rejections;
}

/// Pure, side-effect-free SEND total-budget gate shared by the 1:1 and group
/// composers (149). Sums the final budget bytes of [media] and returns true when
/// the total exceeds [kGroupMediaTotalMessageLimitBytes] — the "each attachment
/// is individually within its cap but together they overflow" case that no
/// per-index [MediaRejection] captures. Callers surface the strip-level total
/// note ONLY when there are no per-index rejections (an over-cap single
/// attachment is reported on its own chip instead, which already disables Send),
/// so the two signals never double up.
bool pendingMediaTotalSizeOverflow(List<PendingComposerMedia> media) {
  var totalBytes = 0;
  for (final pending in media) {
    totalBytes += pending.budgetBytes;
    if (totalBytes > kGroupMediaTotalMessageLimitBytes) return true;
  }
  return false;
}
