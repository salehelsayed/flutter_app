import 'media_attachment.dart';

enum IncomingDirectMediaBlobCustodyStageOutcome {
  applied,
  idempotent,

  /// The author's deletion already won this target. Nothing was staged and
  /// nothing may be published, but the event is durably settled — the caller
  /// still owes its initial message receipt.
  supersededByDeletion,
  refused;

  bool get isDurable =>
      this == IncomingDirectMediaBlobCustodyStageOutcome.applied ||
      this == IncomingDirectMediaBlobCustodyStageOutcome.idempotent;

  /// True only while the caller may publish media, UI, or notifications.
  bool get authorizesPublication => isDurable;

  /// True while the event is durably settled, whether by staging or by an
  /// already-durable deletion.
  bool get settlesEvent =>
      isDurable ||
      this == IncomingDirectMediaBlobCustodyStageOutcome.supersededByDeletion;
}

/// Result of the all-or-zero incoming parent, attachment, and blob-custody
/// publication boundary.
final class IncomingDirectMediaBlobCustodyStageResult {
  const IncomingDirectMediaBlobCustodyStageResult({
    required this.outcome,
    this.attachments = const <MediaAttachment>[],
  });

  const IncomingDirectMediaBlobCustodyStageResult.refused()
    : outcome = IncomingDirectMediaBlobCustodyStageOutcome.refused,
      attachments = const <MediaAttachment>[];

  final IncomingDirectMediaBlobCustodyStageOutcome outcome;
  final List<MediaAttachment> attachments;
}
