import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

/// A single rendered line inside a feed "letter" — one source message's body
/// text plus its (already path-resolved) media attachments.
///
/// The feed renders media the SAME way the 1:1 chat and group conversation
/// screens do (image/video grid + inline voice player), so each letter line
/// must carry the message's [media], not just its [text]. A caption-less media
/// message has an empty [text]; a plain text message has empty [media].
class LetterLine {
  /// The source message id (used for stable widget keys and media tap routing).
  final String messageId;

  /// The body text. Empty for a caption-less media message.
  final String text;

  /// The message's media attachments, already resolved for display by the feed
  /// load path (`load_feed_use_case.dart`).
  final List<MediaAttachment> media;

  const LetterLine({
    required this.messageId,
    required this.text,
    this.media = const [],
  });

  /// True when this line carries at least one media attachment.
  bool get hasMedia => media.isNotEmpty;
}
