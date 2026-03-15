import 'package:flutter/material.dart';

import 'package:flutter_app/core/utils/ring_avatar_generator.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';
import 'package:flutter_app/shared/widgets/media/media_grid_cell.dart';

class PostCard extends StatelessWidget {
  static const Color _onlineDotColor = Color(0xFF1DB954);
  static const Color _friendBadgeColor = Color(0xFF1DB954);
  static const EdgeInsets _cardMargin = EdgeInsets.fromLTRB(8, 0, 8, 12);
  static const EdgeInsets _cardPadding = EdgeInsets.all(16);
  static const double _actionIconSize = 15;

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
    final now = (nowProvider ?? DateTime.now).call();
    final borderColor = isFocused
        ? Colors.white.withOpacity(0.12)
        : Colors.white.withOpacity(0.08);
    final authorColor = RingAvatarGenerator.glowColorForPeerId(
      post.authorPeerId,
    );
    final scopeLabel = post.audience.scopeLabel;
    final isPassedAlong = post.passedByUsername != null;
    final canPassAlong =
        onPassAlong != null &&
        post.audience.kind != PostAudienceKind.pickPeople &&
        post.senderPeerId == post.authorPeerId;

    return Padding(
      padding: _cardMargin,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: _cardPadding,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isPassedAlong) ...[
              Text(
                '${post.passedByUsername!} passed this along',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.48),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      foregroundDecoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: authorColor.withOpacity(0.27),
                          width: 2,
                        ),
                      ),
                      child: UserAvatar(
                        peerId: post.authorPeerId,
                        size: 40,
                        showGlow: false,
                        showPhotoFrame: false,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _onlineDotColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF0A0A0F),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              post.authorUsername,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            _formatRelativeTimestamp(
                              isPassedAlong ? post.visibleAt : post.createdAt,
                              now,
                            ),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.30),
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (!isPassedAlong)
                            const _Badge(label: 'Friend', isPrimary: true),
                          if (scopeLabel != null) _Badge(label: scopeLabel),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (post.nearbyDistanceLabel != null) ...[
              const SizedBox(height: 8),
              Text(
                post.nearbyDistanceLabel!,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.46),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (post.text.isNotEmpty)
              LinkableText(
                text: post.text,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.94),
                  fontSize: 15,
                  height: 1.55,
                ),
              ),
            if (post.media.isNotEmpty) ...[
              const SizedBox(height: 14),
              _PostMediaContent(post: post),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.05)),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _MetricAction(
                          icon: Icons.favorite_border,
                          onTap: onToggleHeart,
                          color: Colors.white.withOpacity(
                            post.viewerHasHearted ? 0.48 : 0.35,
                          ),
                          label: post.heartCount.toString(),
                          labelKey: const ValueKey<String>('post-heart-count'),
                          iconSize: _actionIconSize,
                        ),
                        _MetricAction(
                          icon: Icons.mode_comment_outlined,
                          onTap: onOpenComments,
                          color: Colors.white.withOpacity(0.35),
                          label: post.commentCount.toString(),
                          labelKey: const ValueKey<String>(
                            'post-comment-count',
                          ),
                          iconSize: _actionIconSize,
                        ),
                        if (canPassAlong ||
                            (showShareCount && post.shareCount > 0))
                          _MetricAction(
                            icon: Icons.repeat,
                            onTap: onPassAlong,
                            color: Colors.white.withOpacity(0.35),
                            label: showShareCount
                                ? post.shareCount.toString()
                                : null,
                            labelKey: const ValueKey<String>(
                              'post-share-count',
                            ),
                            iconSize: _actionIconSize,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _expiryCopy(post.expiresAt, now).toLowerCase(),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.25),
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  if (onPinPost != null) ...[
                    const SizedBox(width: 10),
                    _MetricAction(
                      icon: Icons.bookmark_border,
                      onTap: onPinPost,
                      color: Colors.white.withOpacity(0.30),
                      iconSize: 14,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatRelativeTimestamp(String rawTimestamp, DateTime now) {
    final timestamp = DateTime.tryParse(rawTimestamp)?.toUtc();
    if (timestamp == null) {
      return rawTimestamp;
    }
    final diff = now.toUtc().difference(timestamp);
    if (diff.inMinutes < 1) {
      return 'just now';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }
    return '${(diff.inDays / 7).floor()}w ago';
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
      final remainingHours = diff.inHours - (diff.inDays * 24);
      if (remainingHours > 0) {
        return 'Expires in ${diff.inDays}d ${remainingHours}h';
      }
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
  final bool isPrimary;

  const _Badge({required this.label, this.isPrimary = false});

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isPrimary
        ? PostCard._friendBadgeColor.withOpacity(0.13)
        : Colors.white.withOpacity(0.03);
    final borderColor = isPrimary
        ? PostCard._friendBadgeColor.withOpacity(0.20)
        : Colors.white.withOpacity(0.06);
    final textColor = isPrimary
        ? PostCard._friendBadgeColor
        : Colors.white.withOpacity(0.52);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 1,
        ),
      ),
    );
  }
}

class _MetricAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final String? label;
  final Key? labelKey;
  final double iconSize;

  const _MetricAction({
    required this.icon,
    required this.onTap,
    required this.color,
    this.label,
    this.labelKey,
    this.iconSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedColor = onTap == null
        ? const Color.fromRGBO(255, 255, 255, 0.28)
        : color;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: iconSize, color: resolvedColor),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(
                  label!,
                  key: labelKey,
                  style: TextStyle(
                    color: resolvedColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
