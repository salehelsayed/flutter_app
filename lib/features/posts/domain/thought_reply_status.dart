import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

import 'package:flutter_app/features/posts/domain/thought_reply_draft.dart';
import 'package:flutter_app/features/stickers/domain/sticker_catalog.dart';

typedef ThoughtTextReplySender =
    Future<ThoughtReplyStatus> Function(
      String text,
      String postId,
      String messageId,
      ThoughtReplyDraft? draft,
    );

typedef ThoughtStickerReplySender =
    Future<ThoughtReplyStatus> Function(
      ThoughtStickerSelection selection,
      String postId,
      String messageId,
    );

/// Local art for the sticker picked by the user. Only the ordinary sticker
/// marker and attachment are authored into the direct message.
class ThoughtStickerSelection {
  const ThoughtStickerSelection.bundled(StickerEntry this.entry)
    : customId = null,
      customFilePath = null;

  const ThoughtStickerSelection.custom(
    String this.customId,
    String this.customFilePath,
  ) : entry = null;

  final StickerEntry? entry;
  final String? customId;
  final String? customFilePath;
}

typedef ThoughtReplySender =
    Future<ThoughtReplyStatus> Function(
      String text,
      String postId,
      String messageId,
    );

enum ThoughtReplyStatus {
  sent,
  queued,
  failed;

  static ThoughtReplyStatus fromMessage(ConversationMessage message) {
    if (message.isDeleted || message.isHidden) return failed;
    return switch (message.status) {
      'delivered' || 'read' || 'inboxed' => sent,
      'failed' => failed,
      _ => queued,
    };
  }
}
