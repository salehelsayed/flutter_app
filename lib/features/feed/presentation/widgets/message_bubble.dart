import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
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
  final String? status;
  final String? senderLabel;
  final String? senderPeerId;
  final String? quotedText;
  final bool isQuoteUnavailable;
  final List<MediaAttachment> media;
  final void Function(int index)? onMediaTap;

  const MessageBubble({
    super.key,
    required this.text,
    required this.time,
    this.isUnread = false,
    this.isIncoming = true,
    this.status,
    this.senderLabel,
    this.senderPeerId,
    this.quotedText,
    this.isQuoteUnavailable = false,
    this.media = const [],
    this.onMediaTap,
  });

  List<MediaAttachment> get _imageVideoMedia =>
      media.where((a) => a.mediaType == 'image' || a.mediaType == 'video').toList();
  List<MediaAttachment> get _audioMedia =>
      media.where((a) => a.mediaType == 'audio').toList();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: _backgroundColor,
            border: Border.all(color: _borderColor),
            boxShadow: null,
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
                            FeedColors.accentTeal.withValues(alpha: 0.08),
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
                            FeedColors.accentTeal.withValues(alpha: 0.04),
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
                        ? FeedColors.accentTeal
                        : FeedColors.accentTeal.withValues(alpha: 0.25),
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
                      child: _buildQuoteBar(),
                    ),
                  // Media grid
                  if (_imageVideoMedia.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: MediaGrid(media: _imageVideoMedia, onTap: onMediaTap),
                    ),
                  // Audio players
                  for (final audio in _audioMedia)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                      child: AudioPlayerWidget(attachment: audio),
                    ),
                  // Inline name + text + time
                  Padding(
                    padding: _contentPadding,
                    child: _buildInlineContent(),
                  ),
                  // Delivery status (sent only)
                  if (!isIncoming && status != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Semantics(
                          label: 'Message status: ${_statusSemantic(status!)}',
                          child: Icon(
                            _statusIcon(status!),
                            size: 14,
                            color: _statusColor(status!),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  EdgeInsets get _contentPadding {
    final hasMediaAbove = (quotedText != null || isQuoteUnavailable) ||
        _imageVideoMedia.isNotEmpty ||
        _audioMedia.isNotEmpty;
    return EdgeInsets.fromLTRB(
      12,
      hasMediaAbove ? 6 : 8,
      12,
      (!isIncoming && status != null) ? 2 : 8,
    );
  }

  Widget _buildInlineContent() {
    final name = senderLabel ?? (isIncoming ? '' : 'You');
    final nameStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: isIncoming
          ? const Color.fromRGBO(255, 255, 255, 0.9)
          : const Color.fromRGBO(255, 255, 255, 0.6),
      height: 1.5,
    );
    final bodyStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: isIncoming
          ? const Color.fromRGBO(255, 255, 255, 0.90)
          : const Color.fromRGBO(255, 255, 255, 0.80),
      height: 1.5,
    );
    const timeStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w400,
      color: Color.fromRGBO(255, 255, 255, 0.35),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (text.isNotEmpty)
          Text.rich(
            TextSpan(
              children: [
                if (name.isNotEmpty)
                  TextSpan(text: '$name: ', style: nameStyle),
                TextSpan(text: text, style: bodyStyle),
              ],
            ),
          )
        else if (name.isNotEmpty)
          Text(name, style: nameStyle),
        const SizedBox(height: 2),
        Align(
          alignment: Alignment.centerRight,
          child: Text(time, style: timeStyle),
        ),
      ],
    );
  }

  Color get _backgroundColor {
    return isIncoming ? FeedColors.messageReceivedBg : FeedColors.messageSentBg;
  }

  Color get _borderColor {
    return isIncoming
        ? const Color.fromRGBO(255, 255, 255, 0.10)
        : const Color.fromRGBO(255, 255, 255, 0.08);
  }

  Widget _buildQuoteBar() {
    final displayText =
        isQuoteUnavailable ? 'Message unavailable' : quotedText!;
    return Row(
      children: [
        Container(
          width: 2,
          height: 16,
          decoration: BoxDecoration(
            color: const Color.fromRGBO(255, 255, 255, 0.15),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            displayText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              fontStyle:
                  isQuoteUnavailable ? FontStyle.italic : FontStyle.normal,
              color: Color.fromRGBO(
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
    if (status == 'delivered') return Icons.done_all_rounded;
    if (status == 'queued') return Icons.done_all_rounded;
    if (status == 'failed') return Icons.error_outline_rounded;
    return Icons.done_rounded;
  }

  static Color _statusColor(String status) {
    if (status == 'delivered') {
      return const Color.fromRGBO(255, 255, 255, 0.45);
    }
    if (status == 'queued') {
      return const Color.fromRGBO(255, 255, 255, 0.45);
    }
    if (status == 'failed') return const Color.fromRGBO(255, 100, 100, 0.60);
    return const Color.fromRGBO(255, 255, 255, 0.25);
  }

  static String _statusSemantic(String status) {
    if (status == 'delivered') return 'delivered';
    if (status == 'queued') return 'delivered';
    if (status == 'failed') return 'failed';
    if (status == 'sending') return 'sending';
    if (status == 'sent') return 'sent';
    return status;
  }
}
