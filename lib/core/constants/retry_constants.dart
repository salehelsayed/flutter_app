/// Maximum number of attachments per message that the re-upload helper will
/// attempt. Messages with more attachments are skipped as a defensive ceiling.
const int kReuploadMaxAttachmentsPerMessage = 10;

/// Maximum number of transient upload retry attempts before marking
/// an attachment as `upload_failed` (terminal).
const kMaxUploadRetries = 3;

/// Maximum number of transient download retry attempts before marking
/// an attachment as `download_failed` (terminal). A plain `failed` row is
/// retryable only while its `download_retry_count` stays below this ceiling.
const int kMaxDownloadRetries = 3;
