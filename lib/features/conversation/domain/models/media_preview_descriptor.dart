import 'media_attachment.dart';

/// Lightweight, key-free summary of a message's media attachments, used to
/// render a chat-list preview label ("Photo", "Voice message", "3 photos")
/// without hydrating any encryption keys.
///
/// The type/GIF/mixed rules deliberately mirror `notificationBodyForMessage`
/// (`show_notification_use_case.dart`) so the orbit chat-list label and the
/// 1:1 notification body stay in lockstep (see 129 plan INV-4).
class MediaPreviewDescriptor {
  /// Logical media type when every attachment agrees:
  /// `'image' | 'video' | 'audio' | 'file'`. Null when the message mixes types
  /// (then [isMixed] is true).
  final String? type;

  /// Number of attachments on the message (always ≥ 1 for a real descriptor).
  final int count;

  /// True when [type] is `'image'` and every attachment is an animated GIF.
  final bool isGif;

  /// True when the message's attachments span more than one logical type.
  final bool isMixed;

  const MediaPreviewDescriptor({
    required this.type,
    required this.count,
    this.isGif = false,
    this.isMixed = false,
  });

  /// Builds a descriptor from a message's attachments, or null when there are
  /// none. The single-type / GIF / mixed determination mirrors
  /// `notificationBodyForMessage` exactly so the vocabularies cannot drift.
  static MediaPreviewDescriptor? fromAttachments(List<MediaAttachment> media) {
    if (media.isEmpty) return null;
    final firstType = media.first.mediaType;
    final allSameType = media.every((a) => a.mediaType == firstType);
    if (!allSameType) {
      return MediaPreviewDescriptor(
        type: null,
        count: media.length,
        isMixed: true,
      );
    }
    final isGif = firstType == 'image' && media.every((a) => a.isAnimated);
    return MediaPreviewDescriptor(
      type: firstType,
      count: media.length,
      isGif: isGif,
    );
  }
}
