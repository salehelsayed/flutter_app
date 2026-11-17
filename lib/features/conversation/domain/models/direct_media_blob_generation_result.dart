import 'package:flutter_app/core/database/direct_media_blob_custody.dart';

import 'media_attachment.dart';

enum DirectMediaBlobGenerationStageOutcome { applied, idempotent, refused }

final class DirectMediaBlobGenerationStageResult {
  const DirectMediaBlobGenerationStageResult({
    required this.outcome,
    this.attachments = const <MediaAttachment>[],
    this.custodyRows = const <DirectMediaBlobCustodyRow>[],
    this.projectionAvailable = true,
  });

  /// SQL admitted this owner; unavailable hydration must not authorize upload.
  const DirectMediaBlobGenerationStageResult.authorityOnly({required this.outcome})
    : attachments = const <MediaAttachment>[],
      custodyRows = const <DirectMediaBlobCustodyRow>[],
      projectionAvailable = false;

  const DirectMediaBlobGenerationStageResult.refused()
    : projectionAvailable = true,
      outcome = DirectMediaBlobGenerationStageOutcome.refused,
      attachments = const <MediaAttachment>[],
      custodyRows = const <DirectMediaBlobCustodyRow>[];

  final DirectMediaBlobGenerationStageOutcome outcome;
  final List<MediaAttachment> attachments;
  final List<DirectMediaBlobCustodyRow> custodyRows;
  final bool projectionAvailable;

  bool get hasDurableAuthority => outcome != DirectMediaBlobGenerationStageOutcome.refused;
  bool get authorizesStrictUpload => projectionAvailable && hasDurableAuthority;
}

/// Result of the Plan 348 absent-parent entry into the existing v111 owner.
///
/// A repository may return durable authority without a hydrated attachment
/// projection when a post-commit secure-store read is unavailable. Callers must
/// retain that work for retry and may upload only when [authorizesStrictUpload]
/// is true.
final class FreshOutgoingDirectMediaBlobGenerationStageResult {
  const FreshOutgoingDirectMediaBlobGenerationStageResult({
    required this.outcome,
    required this.hasDurableAuthority,
    this.attachments = const <MediaAttachment>[],
    this.custodyRows = const <DirectMediaBlobCustodyRow>[],
  });

  const FreshOutgoingDirectMediaBlobGenerationStageResult.refused()
    : outcome = DirectMediaBlobGenerationStageOutcome.refused,
      hasDurableAuthority = false,
      attachments = const <MediaAttachment>[],
      custodyRows = const <DirectMediaBlobCustodyRow>[];

  const FreshOutgoingDirectMediaBlobGenerationStageResult.authorityOnly({
    this.outcome = DirectMediaBlobGenerationStageOutcome.idempotent,
  }) : hasDurableAuthority = true,
       attachments = const <MediaAttachment>[],
       custodyRows = const <DirectMediaBlobCustodyRow>[];

  final DirectMediaBlobGenerationStageOutcome outcome;
  final bool hasDurableAuthority;
  final List<MediaAttachment> attachments;
  final List<DirectMediaBlobCustodyRow> custodyRows;

  bool get authorizesStrictUpload =>
      hasDurableAuthority &&
      outcome != DirectMediaBlobGenerationStageOutcome.refused &&
      attachments.isNotEmpty &&
      attachments.length == custodyRows.length;
}
