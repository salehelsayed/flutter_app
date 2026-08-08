import 'media_attachment.dart';

enum IncomingDirectMediaBlobCustodyStageOutcome {
  applied,
  idempotent,
  refused;

  bool get isDurable =>
      this == IncomingDirectMediaBlobCustodyStageOutcome.applied ||
      this == IncomingDirectMediaBlobCustodyStageOutcome.idempotent;
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
