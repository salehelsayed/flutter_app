import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

const String kEmptyGroupMediaAclErrorCode = 'EMPTY_GROUP_MEDIA_ACL';

/// The boundary at which an outgoing conversation-media upload failed.
enum UploadMediaStage {
  validation,
  localSource,
  encryption,
  transport,
  durableCopy,
  consumerBoundary,
}

/// The durable retry decision produced by the upload boundary.
enum UploadMediaDisposition {
  /// Wait for connectivity. This disposition never consumes retry budget.
  connectivityRetryable,

  /// Retry up to the configured upload retry ceiling.
  boundedRetryable,

  /// The current attachment cannot be retried automatically.
  terminal,
}

sealed class UploadMediaOutcome {
  const UploadMediaOutcome();

  MediaAttachment? get attachmentOrNull;
}

final class UploadMediaSucceeded extends UploadMediaOutcome {
  const UploadMediaSucceeded(this.attachment);

  final MediaAttachment attachment;

  @override
  MediaAttachment get attachmentOrNull => attachment;
}

final class UploadMediaFailed extends UploadMediaOutcome {
  const UploadMediaFailed({
    required this.stage,
    required this.disposition,
    required this.errorCode,
  });

  final UploadMediaStage stage;
  final UploadMediaDisposition disposition;
  final String errorCode;

  @override
  MediaAttachment? get attachmentOrNull => null;
}
