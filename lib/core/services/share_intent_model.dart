/// Types of shared content from external apps.
enum ShareIntentType { text, files, mixed }

/// Internal-only provenance for one explicit received-media Forward action.
///
/// The token is random per action and intentionally contains no source message,
/// sender, conversation, attachment, or caption identity.
class ForwardProvenance {
  final String operationDedupKey;

  const ForwardProvenance({required this.operationDedupKey});
}

/// Local-only stable authority for one explicit direct received-media Forward.
///
/// Paths, MIME values, protection flags, keys, and captions are deliberately
/// absent. The dispatch boundary reloads these exact identities from durable
/// direct-owned state immediately before it snapshots any plaintext bytes.
/// This object is never serialized into a chat or group payload.
class DirectForwardSourceAuthority {
  DirectForwardSourceAuthority({
    required this.contactPeerId,
    required this.messageId,
    required Iterable<String> attachmentIds,
  }) : attachmentIds = List.unmodifiable(attachmentIds);

  final String contactPeerId;
  final String messageId;
  final List<String> attachmentIds;

  @override
  String toString() =>
      'DirectForwardSourceAuthority(attachmentCount: ${attachmentIds.length})';
}

/// Represents content shared into the app from an external source.
///
/// Created from `receive_sharing_intent` plugin data and passed through
/// the share target picker flow.
class ShareIntent {
  /// The type of shared content.
  final ShareIntentType type;

  /// Shared text content or URL (null for file-only shares).
  final String? text;

  /// Local file paths for shared files.
  final List<String> filePaths;

  /// Null for external OS shares. Non-null only for an in-app Forward action.
  final ForwardProvenance? forwardProvenance;

  /// Stable local authority for direct received-media forwarding. This is
  /// consumed before ordinary share preprocessing and never crosses transport.
  final DirectForwardSourceAuthority? directForwardSourceAuthority;

  const ShareIntent({
    required this.type,
    this.text,
    this.filePaths = const [],
    this.forwardProvenance,
    this.directForwardSourceAuthority,
  });

  /// Whether this intent contains text content.
  bool get hasText => text != null && text!.isNotEmpty;

  /// Whether this intent contains file attachments.
  bool get hasFiles => filePaths.isNotEmpty;

  /// Returns a copy with updated fields while keeping the type in sync.
  ShareIntent copyWith({
    Object? text = _shareIntentTextUnchanged,
    List<String>? filePaths,
    Object? forwardProvenance = _shareIntentProvenanceUnchanged,
    Object? directForwardSourceAuthority =
        _shareIntentDirectForwardAuthorityUnchanged,
  }) {
    final nextText = identical(text, _shareIntentTextUnchanged)
        ? this.text
        : text as String?;
    final nextFilePaths = filePaths ?? this.filePaths;
    return ShareIntent(
      type: _resolveType(text: nextText, filePaths: nextFilePaths),
      text: nextText,
      filePaths: nextFilePaths,
      forwardProvenance:
          identical(forwardProvenance, _shareIntentProvenanceUnchanged)
          ? this.forwardProvenance
          : forwardProvenance as ForwardProvenance?,
      directForwardSourceAuthority:
          identical(
            directForwardSourceAuthority,
            _shareIntentDirectForwardAuthorityUnchanged,
          )
          ? this.directForwardSourceAuthority
          : directForwardSourceAuthority as DirectForwardSourceAuthority?,
    );
  }

  static ShareIntentType _resolveType({
    required String? text,
    required List<String> filePaths,
  }) {
    final hasText = text != null && text.isNotEmpty;
    final hasFiles = filePaths.isNotEmpty;
    if (hasText && hasFiles) {
      return ShareIntentType.mixed;
    }
    if (hasFiles) {
      return ShareIntentType.files;
    }
    return ShareIntentType.text;
  }
}

const Object _shareIntentTextUnchanged = Object();
const Object _shareIntentProvenanceUnchanged = Object();
const Object _shareIntentDirectForwardAuthorityUnchanged = Object();
