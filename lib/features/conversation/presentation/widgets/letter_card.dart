import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';

/// A full-width glassmorphic letter card for conversation messages.
///
/// Both received and sent messages use the same card layout.
/// Authorship is distinguished by accent edge (left=received, right=sent),
/// background opacity, and text brightness.
class LetterCard extends StatelessWidget {
  final String senderPeerId;
  final String senderName;
  final String text;
  final String time;
  final bool isIncoming;
  final String? status;
  final String? transport;
  final String? quotedText;
  final bool isQuoteUnavailable;
  final bool isEdited;
  final bool isDeleted;
  final List<MediaAttachment> media;
  final void Function(int index)? onMediaTap;
  final List<MessageReaction> reactions;
  final String? ownPeerId;
  final VoidCallback? onLongPress;
  final void Function(String emoji)? onReactionTap;
  final VoidCallback? onRetryFailedMessage;
  final VoidCallback? onRetryFailedMedia;
  final VoidCallback? onDeleteFailedMedia;
  final void Function(String attachmentId)? onRetryUnavailableMedia;
  final String? failedMessageActionKeySuffix;
  final String? failedMediaActionKeySuffix;
  final bool requireVerifiedContentHash;

  const LetterCard({
    super.key,
    required this.senderPeerId,
    required this.senderName,
    required this.text,
    required this.time,
    required this.isIncoming,
    this.status,
    this.transport,
    this.quotedText,
    this.isQuoteUnavailable = false,
    this.isEdited = false,
    this.isDeleted = false,
    this.media = const [],
    this.onMediaTap,
    this.reactions = const [],
    this.ownPeerId,
    this.onLongPress,
    this.onReactionTap,
    this.onRetryFailedMessage,
    this.onRetryFailedMedia,
    this.onDeleteFailedMedia,
    this.onRetryUnavailableMedia,
    this.failedMessageActionKeySuffix,
    this.failedMediaActionKeySuffix,
    this.requireVerifiedContentHash = false,
  });

  List<MediaAttachment> get _imageVideoMedia => media
      .where((a) => a.mediaType == 'image' || a.mediaType == 'video')
      .toList();
  List<MediaAttachment> get _audioMedia =>
      media.where((a) => a.mediaType == 'audio').toList();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final readableColors = context.backgroundReadableColors;

    return GestureDetector(
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: isIncoming
                  ? readableColors.surfaceRaised
                  : readableColors.surfaceSubtle,
              border: Border.all(color: readableColors.border),
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
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Color.fromRGBO(78, 205, 196, 0.08),
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
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                            colors: [
                              Color.fromRGBO(255, 255, 255, 0.04),
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
                          ? const Color(0xFF4ecdc4)
                          : readableColors.border,
                      borderRadius: BorderRadius.only(
                        topLeft: isIncoming
                            ? const Radius.circular(24)
                            : Radius.zero,
                        bottomLeft: isIncoming
                            ? const Radius.circular(24)
                            : Radius.zero,
                        topRight: isIncoming
                            ? Radius.zero
                            : const Radius.circular(24),
                        bottomRight: isIncoming
                            ? Radius.zero
                            : const Radius.circular(24),
                      ),
                    ),
                  ),
                ),
                // Card content
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: avatar, name, transport
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Row(
                        children: [
                          UserAvatar(peerId: senderPeerId, size: 32),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              senderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isIncoming
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: isIncoming
                                    ? readableColors.textPrimary
                                    : readableColors.textSecondary,
                              ),
                            ),
                          ),
                          if (transport != null) ...[
                            const SizedBox(width: 4),
                            Icon(
                              _transportIcon(transport!),
                              size: 10,
                              color: readableColors.iconMuted,
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Quote bar (if quoting another message)
                    if (quotedText != null || isQuoteUnavailable)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                        child: _buildQuoteBar(readableColors),
                      ),
                    // Media grid (images/videos)
                    if (_imageVideoMedia.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                        child: MediaGrid(
                          media: _imageVideoMedia,
                          onTap: onMediaTap,
                          onRetryUnavailableMedia:
                              onRetryUnavailableMedia != null
                              ? (attachment) =>
                                    onRetryUnavailableMedia!(attachment.id)
                              : null,
                          requireVerifiedContentHash:
                              requireVerifiedContentHash,
                        ),
                      ),
                    // Audio players
                    for (final audio in _audioMedia)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: AudioPlayerWidget(
                          key: ValueKey(audio.id),
                          attachment: audio,
                          onRetryUnavailableMedia:
                              onRetryUnavailableMedia != null
                              ? () => onRetryUnavailableMedia!(audio.id)
                              : null,
                          requireVerifiedContentHash:
                              requireVerifiedContentHash,
                        ),
                      ),
                    // Body text (only if non-empty)
                    if (text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: isDeleted
                            ? Text(
                                text,
                                textDirection: detectTextDirection(text),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                  fontStyle: FontStyle.italic,
                                  color: readableColors.textMuted,
                                  height: 1.65,
                                  letterSpacing: 0.2,
                                ),
                              )
                            : LinkableText(
                                text: text,
                                textDirection: detectTextDirection(text),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                  color: isIncoming
                                      ? readableColors.textPrimary
                                      : readableColors.textSecondary,
                                  height: 1.65,
                                  letterSpacing: 0.2,
                                ),
                              ),
                      )
                    else if (isDeleted)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Text(
                          l10n.conversation_message_deleted,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            fontStyle: FontStyle.italic,
                            color: readableColors.textMuted,
                            height: 1.65,
                            letterSpacing: 0.2,
                          ),
                        ),
                      )
                    else if (media.isNotEmpty)
                      const SizedBox(height: 12),
                    if (onRetryFailedMessage != null ||
                        onRetryFailedMedia != null ||
                        onDeleteFailedMedia != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (onRetryFailedMessage != null)
                              _buildFailedMessageAction(
                                key: ValueKey(
                                  'failed-message-retry-${failedMessageActionKeySuffix ?? 'message'}',
                                ),
                                icon: Icons.refresh_rounded,
                                label: l10n.btn_retry,
                                semanticLabel:
                                    l10n.failed_message_retry_semantics,
                                color: const Color(0xFF4ECDC4),
                                onTap: onRetryFailedMessage!,
                              ),
                            if (onRetryFailedMedia != null)
                              _buildFailedMessageAction(
                                key: ValueKey(
                                  'failed-media-retry-${failedMediaActionKeySuffix ?? 'message'}',
                                ),
                                icon: Icons.refresh_rounded,
                                label: l10n.btn_retry,
                                semanticLabel:
                                    l10n.failed_media_retry_semantics,
                                color: const Color(0xFF4ECDC4),
                                onTap: onRetryFailedMedia!,
                              ),
                            if (onDeleteFailedMedia != null)
                              _buildFailedMessageAction(
                                key: ValueKey(
                                  'failed-media-delete-${failedMediaActionKeySuffix ?? 'message'}',
                                ),
                                icon: Icons.delete_outline_rounded,
                                label: l10n.conversation_context_delete,
                                semanticLabel:
                                    l10n.failed_media_delete_semantics,
                                color: const Color(0xFFFF8A80),
                                onTap: onDeleteFailedMedia!,
                              ),
                          ],
                        ),
                      ),
                    // Footer: inline reactions + timestamp + delivery status
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: (reactions.isNotEmpty && ownPeerId != null)
                                ? Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: _buildReactionChipWidgets(
                                      readableColors,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          if (reactions.isNotEmpty && ownPeerId != null)
                            const SizedBox(width: 8),
                          Text(
                            time,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              color: readableColors.textMuted,
                            ),
                          ),
                          if (isEdited && l10n != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              l10n.conversation_edited_indicator,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                color: readableColors.textMuted,
                              ),
                            ),
                          ],
                          if (!isIncoming && status != null) ...[
                            const SizedBox(width: 4),
                            Semantics(
                              label: l10n.message_status_semantics(
                                _statusSemantic(context, status!),
                              ),
                              child: Icon(
                                _statusIcon(status!),
                                size: 14,
                                color: _statusColor(status!, readableColors),
                              ),
                            ),
                          ],
                        ],
                      ),
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

  Widget _buildFailedMessageAction({
    required Key key,
    required IconData icon,
    required String label,
    required String semanticLabel,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: OutlinedButton.icon(
        key: key,
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withAlpha(140)),
          backgroundColor: color.withAlpha(20),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          visualDensity: VisualDensity.compact,
        ),
        icon: Icon(icon, size: 16),
        label: Text(label),
      ),
    );
  }

  List<Widget> _buildReactionChipWidgets(
    BackgroundReadableColors readableColors,
  ) {
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
            color: readableColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isOwn
                  ? const Color.fromRGBO(78, 205, 196, 0.30)
                  : readableColors.border.withValues(alpha: 0.34),
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

  Widget _buildQuoteBar(BackgroundReadableColors readableColors) {
    final displayText = isQuoteUnavailable
        ? 'Message unavailable'
        : quotedText!;
    return Row(
      children: [
        Container(
          width: 2,
          height: 16,
          decoration: BoxDecoration(
            color: readableColors.divider,
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
              color: isQuoteUnavailable
                  ? readableColors.disabledForeground
                  : readableColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  static IconData _transportIcon(String transport) {
    switch (transport) {
      case 'wifi':
      case 'local':
        return Icons.wifi;
      case 'direct':
      case 'reuse':
        // Keep old rows renderable after the send path stopped persisting reuse.
        return Icons.device_hub;
      case 'relay':
        return Icons.cell_tower;
      case 'inbox':
        return Icons.inbox;
      default:
        return Icons.help_outline;
    }
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

  static Color _statusColor(
    String status,
    BackgroundReadableColors readableColors,
  ) {
    if (status == 'delivered') {
      return readableColors.isLightSurface
          ? readableColors.iconMuted
          : const Color.fromRGBO(255, 255, 255, 0.45);
    }
    if (status == 'failed') {
      return readableColors.isLightSurface
          ? const Color(0xFFB42318)
          : const Color.fromRGBO(255, 100, 100, 0.60);
    }
    if (status == 'pending') {
      return readableColors.isLightSurface
          ? const Color(0xFF8A4A00)
          : const Color.fromRGBO(255, 200, 100, 0.50);
    }
    return readableColors.isLightSurface
        ? readableColors.iconMuted
        : const Color.fromRGBO(255, 255, 255, 0.25);
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
