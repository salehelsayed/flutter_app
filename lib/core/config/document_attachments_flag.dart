/// Build-time switch for SENDING document (PDF) attachments (plan 414, D3).
///
/// Default-OFF. Enable with
/// `--dart-define=MKNOON_ENABLE_DOCUMENT_ATTACHMENTS=true`.
///
/// It gates only the composer's "Document" picker. Receiving, showing and
/// opening PDFs is always on, so builds with the switch off can read PDFs
/// that newer builds send. Turn it on once testers run a build that can
/// receive them: older group builds drop a PDF message entirely.
const bool kDocumentAttachmentsEnabled = bool.fromEnvironment(
  'MKNOON_ENABLE_DOCUMENT_ATTACHMENTS',
);
