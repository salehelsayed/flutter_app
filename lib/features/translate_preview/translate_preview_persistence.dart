enum PreviewOwnerKind { thought, voiceAttachment }

final class PreviewOwner {
  const PreviewOwner.thought(this.id)
    : kind = PreviewOwnerKind.thought,
      messageId = null;
  const PreviewOwner.voiceAttachment(this.id, {required this.messageId})
    : kind = PreviewOwnerKind.voiceAttachment;

  final PreviewOwnerKind kind;
  final String id;
  final String? messageId;

  @override
  bool operator ==(Object other) =>
      other is PreviewOwner &&
      kind == other.kind &&
      id == other.id &&
      messageId == other.messageId;
  @override
  int get hashCode => Object.hash(kind, id, messageId);
}

/// Local results belong to an existing item, independently of model delivery.
final class TranslatePreviewPersistence {
  const TranslatePreviewPersistence({
    required this.loadTranscript,
    required this.saveTranscript,
    required this.loadTranslation,
    required this.saveTranslation,
  });

  final Future<String?> Function(PreviewOwner owner) loadTranscript;
  final Future<bool> Function(PreviewOwner owner, String result) saveTranscript;
  final Future<String?> Function(
    PreviewOwner owner,
    String source,
    String targetLanguage,
  )
  loadTranslation;
  final Future<bool> Function(
    PreviewOwner owner,
    String source,
    String targetLanguage,
    String result,
  )
  saveTranslation;
}

/// Bound to the current account's encrypted database by production bootstrap.
TranslatePreviewPersistence? translatePreviewPersistence;
