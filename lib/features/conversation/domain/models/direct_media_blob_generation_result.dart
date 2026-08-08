import 'package:flutter_app/core/database/direct_media_blob_custody.dart';

import 'media_attachment.dart';

enum DirectMediaBlobGenerationStageOutcome { applied, idempotent, refused }

final class DirectMediaBlobGenerationStageResult {
  const DirectMediaBlobGenerationStageResult({
    required this.outcome,
    this.attachments = const <MediaAttachment>[],
    this.custodyRows = const <DirectMediaBlobCustodyRow>[],
  });

  const DirectMediaBlobGenerationStageResult.refused()
    : outcome = DirectMediaBlobGenerationStageOutcome.refused,
      attachments = const <MediaAttachment>[],
      custodyRows = const <DirectMediaBlobCustodyRow>[];

  final DirectMediaBlobGenerationStageOutcome outcome;
  final List<MediaAttachment> attachments;
  final List<DirectMediaBlobCustodyRow> custodyRows;

  bool get authorizesStrictUpload =>
      outcome == DirectMediaBlobGenerationStageOutcome.applied ||
      outcome == DirectMediaBlobGenerationStageOutcome.idempotent;
}
