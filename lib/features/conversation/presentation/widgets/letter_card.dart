import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
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
  final List<MediaAttachment> media;
  final void Function(int index)? onMediaTap;
  final List<MessageReaction> reactions;
  final String? ownPeerId;
  final VoidCallback? onLongPress;
  final void Function(String emoji)? onReactionTap;

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
    this.media = const [],
    this.onMediaTap,
    this.reactions = const [],
    this.ownPeerId,
    this.onLongPress,
    this.onReactionTap,
  });

  List<MediaAttachment> get _imageVideoMedia => media
      .where((a) => a.mediaType == 'image' || a.mediaType == 'video')
      .toList();
  List<MediaAttachment> get _audioMedia =>
      media.where((a) => a.mediaType == 'audio').toList();

  @override
  Widget build(BuildContext context) {
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
                  ? const Color.fromRGBO(255, 255, 255, 0.06)
                  : const Color.fromRGBO(255, 255, 255, 0.04),
              border: Border.all(
                color: isIncoming
                    ? const Color.fromRGBO(255, 255, 255, 0.10)
                    : const Color.fromRGBO(255, 255, 255, 0.08),
              ),
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
                          : const Color.fromRGBO(255, 255, 255, 0.25),
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
                                    ? const Color.fromRGBO(255, 255, 255, 0.9)
                                    : const Color.fromRGBO(255, 255, 255, 0.6),
                              ),
                            ),
                          ),
                          if (transport != null) ...[
                            const SizedBox(width: 4),
                            Icon(
                              _transportIcon(transport!),
                              size: 10,
                              color: const Color.fromRGBO(255, 255, 255, 0.35),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Quote bar (if quoting another message)
                    if (quotedText != null || isQuoteUnavailable)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                        child: _buildQuoteBar(),
                      ),
                    // Media grid (images/videos)
                    if (_imageVideoMedia.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                        child: MediaGrid(
                          media: _imageVideoMedia,
                          onTap: onMediaTap,
                        ),
                      ),
                    // Audio players
                    for (final audio in _audioMedia)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: AudioPlayerWidget(
                          key: ValueKey(audio.id),
                          attachment: audio,
                        ),
                      ),
                    // Body text (only if non-empty)
                    if (text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: LinkableText(
                          text: text,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            color: isIncoming
                                ? const Color.fromRGBO(255, 255, 255, 0.90)
                                : const Color.fromRGBO(255, 255, 255, 0.80),
                            height: 1.65,
                            letterSpacing: 0.2,
                          ),
                        ),
                      )
                    else if (media.isNotEmpty)
                      const SizedBox(height: 12),
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
                                    children: _buildReactionChipWidgets(),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          if (reactions.isNotEmpty && ownPeerId != null)
                            const SizedBox(width: 8),
                          Text(
                            time,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              color: Color.fromRGBO(255, 255, 255, 0.35),
                            ),
                          ),
                          if (!isIncoming && status != null) ...[
                            const SizedBox(width: 4),
                            Semantics(
                              label:
                                  'Message status: ${_statusSemantic(status!)}',
                              child: Icon(
                                _statusIcon(status!),
                                size: 14,
                                color: _statusColor(status!),
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

  List<Widget> _buildReactionChipWidgets() {
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
            color: const Color.fromRGBO(255, 255, 255, 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isOwn
                  ? const Color.fromRGBO(78, 205, 196, 0.30)
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

  Widget _buildQuoteBar() {
    final displayText = isQuoteUnavailable
        ? 'Message unavailable'
        : quotedText!;
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
              fontStyle: isQuoteUnavailable
                  ? FontStyle.italic
                  : FontStyle.normal,
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

  static IconData _transportIcon(String transport) {
    switch (transport) {
      case 'wifi':
        return Icons.wifi;
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
    return Icons.done_rounded; // 'sent', 'sending'
  }

  static Color _statusColor(String status) {
    if (status == 'delivered') {
      return const Color.fromRGBO(255, 255, 255, 0.45);
    }
    if (status == 'failed') return const Color.fromRGBO(255, 100, 100, 0.60);
    return const Color.fromRGBO(255, 255, 255, 0.25);
  }

  static String _statusSemantic(String status) {
    if (status == 'delivered' || status == 'queued') {
      return 'delivered';
    }
    if (status == 'failed') return 'failed';
    if (status == 'sending') return 'sending';
    if (status == 'sent') return 'sent';
    return status;
  }
}
