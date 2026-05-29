import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';

/// Compact message bubble within an expanded feed card.
///
/// Single-line "Name: message text  time" layout that wraps naturally.
/// Glassmorphic card with accent edge glow and border.
/// - Received (isIncoming=true): teal left accent
/// - Sent (isIncoming=false): white right accent, "You" label
/// Unread received messages get purple border tint with subtle glow.
class MessageBubble extends StatelessWidget {
  final String text;
  final String time;
  final bool isUnread;
  final bool isIncoming;
  final bool isDeleted;
  final String? status;
  final bool isEdited;
  final String? senderLabel;
  final String? senderPeerId;
  final String? quotedText;
  final bool isQuoteUnavailable;
  final List<MediaAttachment> media;
  final void Function(int index)? onMediaTap;
  final List<MessageReaction> reactions;
  final String? ownPeerId;
  final VoidCallback? onLongPress;
  final void Function(String emoji)? onReactionTap;
  final bool requireVerifiedContentHash;

  const MessageBubble({
    super.key,
    required this.text,
    required this.time,
    this.isUnread = false,
    this.isIncoming = true,
    this.isDeleted = false,
    this.status,
    this.isEdited = false,
    this.senderLabel,
    this.senderPeerId,
    this.quotedText,
    this.isQuoteUnavailable = false,
    this.media = const [],
    this.onMediaTap,
    this.reactions = const [],
    this.ownPeerId,
    this.onLongPress,
    this.onReactionTap,
    this.requireVerifiedContentHash = false,
  });

  List<MediaAttachment> get _imageVideoMedia => isDeleted
      ? const <MediaAttachment>[]
      : media
            .where((a) => a.mediaType == 'image' || a.mediaType == 'video')
            .toList();
  List<MediaAttachment> get _audioMedia => isDeleted
      ? const <MediaAttachment>[]
      : media.where((a) => a.mediaType == 'audio').toList();

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final isLightSurface = readableColors.isLightSurface;
    final accentColor = isLightSurface
        ? const Color(0xFF0F8F87)
        : FeedColors.accentTeal;

    return Align(
      alignment: isIncoming ? Alignment.centerLeft : Alignment.centerRight,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: isLightSurface
                  ? readableColors.surfaceBase.withValues(alpha: 0.72)
                  : null,
              border: Border.all(color: _borderColor(context)),
            ),
            child: Stack(
              children: [
                // Accent edge glow
                if (isIncoming)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 60,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              accentColor.withValues(alpha: 0.08),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: 60,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                            colors: [
                              accentColor.withValues(alpha: 0.04),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                // Accent border edge
                Positioned(
                  left: isIncoming ? 0 : null,
                  right: isIncoming ? null : 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: isIncoming
                          ? accentColor
                          : accentColor.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.only(
                        topLeft: isIncoming
                            ? const Radius.circular(14)
                            : Radius.zero,
                        bottomLeft: isIncoming
                            ? const Radius.circular(14)
                            : Radius.zero,
                        topRight: isIncoming
                            ? Radius.zero
                            : const Radius.circular(14),
                        bottomRight: isIncoming
                            ? Radius.zero
                            : const Radius.circular(14),
                      ),
                    ),
                  ),
                ),
                // Card content
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Quote bar
                    if (quotedText != null || isQuoteUnavailable)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: _buildQuoteBar(context),
                      ),
                    // Media grid
                    if (_imageVideoMedia.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                        child: MediaGrid(
                          media: _imageVideoMedia,
                          onTap: onMediaTap,
                          requireVerifiedContentHash:
                              requireVerifiedContentHash,
                        ),
                      ),
                    // Audio players
                    for (final audio in _audioMedia)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                        child: AudioPlayerWidget(
                          attachment: audio,
                          requireVerifiedContentHash:
                              requireVerifiedContentHash,
                        ),
                      ),
                    // Inline name + text + time + status
                    Padding(
                      padding: _contentPadding,
                      child: _buildInlineContent(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  EdgeInsets get _contentPadding {
    final hasMediaAbove =
        (quotedText != null || isQuoteUnavailable) ||
        _imageVideoMedia.isNotEmpty ||
        _audioMedia.isNotEmpty;
    return EdgeInsets.fromLTRB(12, hasMediaAbove ? 6 : 8, 12, 8);
  }

  Widget _buildInlineContent(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final isLightSurface = readableColors.isLightSurface;
    final name =
        senderLabel ??
        (isIncoming ? '' : AppLocalizations.of(context)!.feed_you);
    final nameStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: isLightSurface
          ? readableColors.textPrimary
          : const Color.fromRGBO(255, 255, 255, 0.9),
      height: 1.5,
    );
    final bodyStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: isLightSurface
          ? (isIncoming
                ? readableColors.textPrimary
                : readableColors.textSecondary)
          : (isIncoming
                ? const Color.fromRGBO(255, 255, 255, 0.90)
                : const Color.fromRGBO(255, 255, 255, 0.80)),
      height: 1.5,
    );
    final deletedText = isDeleted
        ? AppLocalizations.of(context)?.conversation_message_deleted ??
              'This message was deleted'
        : null;
    final displayText = isDeleted ? deletedText! : text;
    final hasBody = displayText.isNotEmpty;
    final hasName = name.isNotEmpty;
    final hasStatus = !isDeleted && !isIncoming && status != null;

    final hasReactions =
        !isDeleted && reactions.isNotEmpty && ownPeerId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasName)
          Text(
            '$name:',
            textDirection: detectTextDirection(name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: nameStyle,
          ),
        if (hasName && hasBody) const SizedBox(height: 2),
        if (hasBody)
          isDeleted
              ? Text(
                  displayText,
                  textDirection: detectTextDirection(displayText),
                  style: bodyStyle.copyWith(
                    fontStyle: FontStyle.italic,
                    color: isLightSurface
                        ? readableColors.textMuted
                        : const Color.fromRGBO(255, 255, 255, 0.60),
                  ),
                )
              : LinkableText(
                  text: displayText,
                  textDirection: detectTextDirection(displayText),
                  style: bodyStyle,
                ),
        if (hasName || hasBody) const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: hasReactions
                  ? Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: _buildReactionChipWidgets(context),
                    )
                  : const SizedBox.shrink(),
            ),
            Text(
              time,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: isLightSurface
                    ? readableColors.textMuted
                    : const Color.fromRGBO(255, 255, 255, 0.35),
              ),
            ),
            if (isEdited && !isDeleted) ...[
              const SizedBox(width: 6),
              Text(
                AppLocalizations.of(context)!.conversation_edited_indicator,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: isLightSurface
                      ? readableColors.textMuted
                      : const Color.fromRGBO(255, 255, 255, 0.35),
                ),
              ),
            ],
            if (hasStatus) ...[
              const SizedBox(width: 4),
              Semantics(
                label: AppLocalizations.of(
                  context,
                )!.message_status_semantics(_statusSemantic(context, status!)),
                child: Icon(
                  _statusIcon(status!),
                  size: 14,
                  color: _statusColor(context, status!),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  List<Widget> _buildReactionChipWidgets(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final isLightSurface = readableColors.isLightSurface;
    final groups = <String, List<MessageReaction>>{};
    for (final r in reactions) {
      groups.putIfAbsent(r.emoji, () => []).add(r);
    }

    return groups.entries.map((entry) {
      final emoji = entry.key;
      final list = entry.value;
      final isOwn =
          ownPeerId != null && list.any((r) => r.senderPeerId == ownPeerId);

      return GestureDetector(
        onTap: onReactionTap != null ? () => onReactionTap!(emoji) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isLightSurface
                ? readableColors.surfaceSubtle.withValues(alpha: 0.82)
                : const Color.fromRGBO(255, 255, 255, 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isOwn
                  ? (isLightSurface
                        ? const Color(0xFF0F8F87).withValues(alpha: 0.36)
                        : const Color.fromRGBO(78, 205, 196, 0.30))
                  : Colors.transparent,
            ),
          ),
          child: Text(
            list.length > 1 ? '$emoji ${list.length}' : emoji,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      );
    }).toList();
  }

  Color _borderColor(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    if (readableColors.isLightSurface) {
      return isIncoming
          ? readableColors.border.withValues(alpha: 0.16)
          : readableColors.border.withValues(alpha: 0.12);
    }
    return isIncoming
        ? const Color.fromRGBO(255, 255, 255, 0.10)
        : const Color.fromRGBO(255, 255, 255, 0.08);
  }

  Widget _buildQuoteBar(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final isLightSurface = readableColors.isLightSurface;
    final displayText = isQuoteUnavailable
        ? 'Message unavailable'
        : quotedText!;
    return Row(
      children: [
        Container(
          width: 2,
          height: 16,
          decoration: BoxDecoration(
            color: isLightSurface
                ? readableColors.divider
                : const Color.fromRGBO(255, 255, 255, 0.15),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            displayText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: detectTextDirection(displayText),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              fontStyle: isQuoteUnavailable
                  ? FontStyle.italic
                  : FontStyle.normal,
              color: isLightSurface
                  ? readableColors.textMuted.withValues(
                      alpha: isQuoteUnavailable ? 0.55 : 0.78,
                    )
                  : Color.fromRGBO(
                      255,
                      255,
                      255,
                      isQuoteUnavailable ? 0.20 : 0.35,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  static IconData _statusIcon(String status) {
    // Legacy compatibility: old rows may still have queued status.
    if (status == 'delivered' || status == 'queued') {
      return Icons.done_all_rounded;
    }
    if (status == 'failed') return Icons.error_outline_rounded;
    if (status == 'pending') return Icons.schedule_rounded;
    return Icons.done_rounded; // 'sent', 'sending'
  }

  static Color _statusColor(BuildContext context, String status) {
    final readableColors = context.backgroundReadableColors;
    if (readableColors.isLightSurface) {
      if (status == 'delivered') return readableColors.iconMuted;
      if (status == 'failed') return const Color(0xFFC62828);
      if (status == 'pending') return const Color(0xFF8A5D00);
      return readableColors.iconMuted.withValues(alpha: 0.75);
    }
    if (status == 'delivered') {
      return const Color.fromRGBO(255, 255, 255, 0.45);
    }
    if (status == 'failed') return const Color.fromRGBO(255, 100, 100, 0.60);
    if (status == 'pending') return const Color.fromRGBO(255, 200, 100, 0.50);
    return const Color.fromRGBO(255, 255, 255, 0.25);
  }

  static String _statusSemantic(BuildContext context, String status) {
    final l10n = AppLocalizations.of(context)!;
    if (status == 'delivered' || status == 'queued') {
      return l10n.message_status_delivered;
    }
    if (status == 'failed') return l10n.message_status_failed;
    if (status == 'sending') return l10n.message_status_sending;
    if (status == 'sent') return l10n.message_status_sent;
    if (status == 'pending') return l10n.message_status_pending_inbox;
    return status;
  }
}
