import 'package:flutter/material.dart';

import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';
import 'package:flutter_app/shared/widgets/media/media_grid_cell.dart';

class PostCard extends StatelessWidget {
  final PostModel post;
  final bool isFocused;
  final VoidCallback? onOpenComments;
  final VoidCallback? onToggleHeart;
  final VoidCallback? onPassAlong;
  final VoidCallback? onPinPost;
  final bool showShareCount;
  final DateTime Function()? nowProvider;

  const PostCard({
    super.key,
    required this.post,
    this.isFocused = false,
    this.onOpenComments,
    this.onToggleHeart,
    this.onPassAlong,
    this.onPinPost,
    this.showShareCount = false,
    this.nowProvider,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isFocused
        ? const Color(0xFF8FD6B5)
        : const Color.fromRGBO(255, 255, 255, 0.12);
    final scopeLabel = post.audience.scopeLabel;
    final isPassedAlong = post.passedByUsername != null;
    final canPassAlong =
        onPassAlong != null &&
        post.audience.kind != PostAudienceKind.pickPeople &&
        post.senderPeerId == post.authorPeerId;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171A20),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: isFocused
                ? const Color.fromRGBO(143, 214, 181, 0.18)
                : const Color.fromRGBO(0, 0, 0, 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPassedAlong) ...[
            Text(
              '${post.passedByUsername!} passed this along',
              style: const TextStyle(
                color: Color(0xFF8FD6B5),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  post.authorUsername,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                _formatTimestamp(
                  isPassedAlong ? post.visibleAt : post.createdAt,
                ),
                style: const TextStyle(
                  color: Color.fromRGBO(255, 255, 255, 0.54),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (!isPassedAlong) const _Badge(label: 'Direct Friend'),
              if (scopeLabel != null) ...[
                const SizedBox(width: 8),
                _Badge(label: scopeLabel),
              ],
            ],
          ),
          if (post.nearbyDistanceLabel != null) ...[
            const SizedBox(height: 8),
            Text(
              post.nearbyDistanceLabel!,
              style: const TextStyle(
                color: Color(0xFF8FD6B5),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (post.text.isNotEmpty)
            Text(
              post.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.45,
              ),
            ),
          if (post.media.isNotEmpty) ...[
            const SizedBox(height: 16),
            _PostMediaContent(post: post),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                onPressed: onToggleHeart,
                icon: Icon(
                  post.viewerHasHearted
                      ? Icons.favorite
                      : Icons.favorite_border,
                ),
                color: post.viewerHasHearted
                    ? const Color(0xFFEF7C8E)
                    : const Color(0xFF8FD6B5),
              ),
              Text(
                _heartCountLabel(post.heartCount),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: onOpenComments,
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('Comments'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF8FD6B5),
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _commentCountLabel(post.commentCount),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (canPassAlong) ...[
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: onPassAlong,
                  icon: const Icon(Icons.redo, size: 18),
                  label: const Text('Pass along'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF8FD6B5),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
              if (onPinPost != null) ...[
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: onPinPost,
                  icon: const Icon(Icons.push_pin_outlined, size: 18),
                  label: const Text('Pin'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF8FD6B5),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          if (showShareCount && post.shareCount > 0) ...[
            Text(
              _shareCountLabel(post.shareCount),
              style: const TextStyle(
                color: Color.fromRGBO(255, 255, 255, 0.54),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            _confirmationCopy(post),
            style: const TextStyle(
              color: Color.fromRGBO(255, 255, 255, 0.54),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _expiryCopy(post.expiresAt, (nowProvider ?? DateTime.now).call()),
            style: const TextStyle(
              color: Color.fromRGBO(255, 255, 255, 0.54),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTimestamp(String rawTimestamp) {
    final timestamp = DateTime.tryParse(rawTimestamp)?.toLocal();
    if (timestamp == null) {
      return rawTimestamp;
    }
    final hour = timestamp.hour == 0 || timestamp.hour == 12
        ? 12
        : timestamp.hour % 12;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final meridiem = timestamp.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $meridiem';
  }

  static String _confirmationCopy(PostModel post) {
    return switch (post.audience.kind) {
      PostAudienceKind.peopleNearby => 'Shared with nearby friends',
      _ when post.audience.selectedPeerIds.isNotEmpty =>
        'Shared with ${post.audience.selectedPeerIds.length} people',
      _ => 'Shared with all friends',
    };
  }

  static String _commentCountLabel(int count) {
    return count == 1 ? '1 comment' : '$count comments';
  }

  static String _heartCountLabel(int count) {
    return count == 1 ? '1 heart' : '$count hearts';
  }

  static String _shareCountLabel(int count) {
    return count == 1 ? '1 share' : '$count shares';
  }

  static String _expiryCopy(String rawTimestamp, DateTime now) {
    final expiry = DateTime.tryParse(rawTimestamp)?.toUtc();
    final current = now.toUtc();
    if (expiry == null) {
      return rawTimestamp;
    }
    final diff = expiry.difference(current);
    if (diff.inSeconds <= 0) {
      return 'Expired';
    }
    if (diff.inDays >= 1) {
      return 'Expires in ${diff.inDays}d';
    }
    if (diff.inHours >= 1) {
      return 'Expires in ${diff.inHours}h';
    }
    if (diff.inMinutes >= 1) {
      return 'Expires in ${diff.inMinutes}m';
    }
    return 'Expires soon';
  }
}

class _PostMediaContent extends StatelessWidget {
  final PostModel post;

  const _PostMediaContent({required this.post});

  @override
  Widget build(BuildContext context) {
    final attachments = post.media
        .map((attachment) => attachment.toSharedMediaAttachment())
        .toList(growable: false);
    switch (post.mediaKind) {
      case 'image_carousel':
        return _ImageCarousel(attachments: post.media);
      case 'voice':
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF11161D),
            borderRadius: BorderRadius.circular(18),
          ),
          child: AudioPlayerWidget(attachment: attachments.single),
        );
      default:
        return MediaGrid(media: attachments);
    }
  }
}

class _ImageCarousel extends StatefulWidget {
  final List<PostMediaAttachmentModel> attachments;

  const _ImageCarousel({required this.attachments});

  @override
  State<_ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<_ImageCarousel> {
  int _activeIndex = 0;

  @override
  Widget build(BuildContext context) {
    final attachments = widget.attachments
        .map((attachment) => attachment.toSharedMediaAttachment())
        .toList(growable: false);
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 220,
            child: PageView.builder(
              itemCount: attachments.length,
              onPageChanged: (index) {
                setState(() => _activeIndex = index);
              },
              itemBuilder: (context, index) {
                return MediaGridCell(
                  attachment: attachments[index],
                  borderRadius: 0,
                );
              },
            ),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(0, 0, 0, 0.45),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${_activeIndex + 1} / ${attachments.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 12,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(attachments.length, (index) {
              final isActive = index == _activeIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: isActive ? 18 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.white
                      : const Color.fromRGBO(255, 255, 255, 0.4),
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;

  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
