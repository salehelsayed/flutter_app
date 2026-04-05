/// Types of shared content from external apps.
enum ShareIntentType { text, files, mixed }

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

  const ShareIntent({required this.type, this.text, this.filePaths = const []});

  /// Whether this intent contains text content.
  bool get hasText => text != null && text!.isNotEmpty;

  /// Whether this intent contains file attachments.
  bool get hasFiles => filePaths.isNotEmpty;

  /// Returns a copy with updated fields while keeping the type in sync.
  ShareIntent copyWith({
    Object? text = _shareIntentTextUnchanged,
    List<String>? filePaths,
  }) {
    final nextText = identical(text, _shareIntentTextUnchanged)
        ? this.text
        : text as String?;
    final nextFilePaths = filePaths ?? this.filePaths;
    return ShareIntent(
      type: _resolveType(text: nextText, filePaths: nextFilePaths),
      text: nextText,
      filePaths: nextFilePaths,
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
