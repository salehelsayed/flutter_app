import 'package:flutter_app/features/conversation/domain/models/conversation_timeline_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/media_preview_descriptor.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/call_timeline_row.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Builds the localized chat-list preview string for an orbit row (friend or
/// group), shared by `FriendRow` and `GroupRow`.
///
/// Precedence:
///   0. 409: a terminal [call] — set only when it is NEWER than the latest
///      message, so by the time it is non-null the ordering is already
///      settled and it outranks even the deleted placeholder;
///   1. soft-deleted latest → localized "message deleted" placeholder;
///   2. a non-empty [caption] wins (returned verbatim so its own RTL/LTR is
///      preserved by the caller's `detectTextDirection`);
///   3. a media label derived from [media];
///   4. otherwise '' — the caller renders no preview line.
///
/// Vocabulary matches `notificationBodyForMessage`
/// (Voice message / Photo / Video / File / GIF / generic attachment), with
/// counts added for multiples — see 129 plan INV-4.
String orbitMediaPreviewLabel({
  required AppLocalizations l10n,
  String? caption,
  MediaPreviewDescriptor? media,
  ConversationCallTimelineEntry? call,
  bool isDeleted = false,
}) {
  // Direction-aware, and deliberately the SAME wording the chat row uses: the
  // two surfaces describing one call differently is how they drift.
  if (call != null) return callTimelineStatusLabel(call, l10n);

  if (isDeleted) return l10n.conversation_message_deleted;

  final hasCaption = (caption?.trim().isNotEmpty) ?? false;
  if (hasCaption) return caption!;

  if (media == null || media.count == 0) return '';
  if (media.isMixed) return l10n.orbit_preview_attachment(media.count);

  switch (media.type) {
    case 'image':
      return media.isGif
          ? l10n.orbit_preview_gif
          : l10n.orbit_preview_photo(media.count);
    case 'video':
      return l10n.orbit_preview_video(media.count);
    case 'audio':
      return l10n.orbit_preview_voice_message;
    case 'file':
      return l10n.orbit_preview_file(media.count);
    default:
      return l10n.orbit_preview_attachment(media.count);
  }
}
