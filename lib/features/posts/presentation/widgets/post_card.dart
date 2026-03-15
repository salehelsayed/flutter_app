import 'package:flutter/material.dart';

import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';
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
    final now = (nowProvider ?? DateTime.now).call();
    final borderColor = isFocused
        ? const Color(0xFF8FD6B5)
        : const Color.fromRGBO(255, 255, 255, 0.10);
    final scopeLabel = post.audience.scopeLabel;
    final isPassedAlong = post.passedByUsername != null;
    final canPassAlong =
        onPassAlong != null &&
        post.audience.kind != PostAudienceKind.pickPeople &&
        post.senderPeerId == post.authorPeerId;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(8, 10, 14, 0.62),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: isFocused
                ? const Color.fromRGBO(143, 214, 181, 0.16)
                : const Color.fromRGBO(0, 0, 0, 0.10),
            blurRadius: 28,
            offset: const Offset(0, 16),
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
            const SizedBox(height: 10),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(peerId: post.authorPeerId, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            post.authorUsername,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _formatRelativeTimestamp(
                            isPassedAlong ? post.visibleAt : post.createdAt,
                            now,
                          ),
                          style: const TextStyle(
                            color: Color.fromRGBO(255, 255, 255, 0.48),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
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
            const SizedBox(height: 10),
            Text(
              post.nearbyDistanceLabel!,
              style: const TextStyle(
                color: Color(0xFF8FD6B5),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (post.text.isNotEmpty)
            LinkableText(
              text: post.text,
              style: const TextStyle(
                color: Color.fromRGBO(255, 255, 255, 0.92),
                fontSize: 17,
                height: 1.58,
                letterSpacing: 0.1,
              ),
            ),
          if (post.media.isNotEmpty) ...[
            const SizedBox(height: 16),
            _PostMediaContent(post: post),
          ],
          const SizedBox(height: 14),
          const Divider(
            height: 1,
            thickness: 1,
            color: Color.fromRGBO(255, 255, 255, 0.08),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final actions = <Widget>[
                _MetricAction(
                  icon: post.viewerHasHearted
                      ? Icons.favorite
                      : Icons.favorite_border,
                  onTap: onToggleHeart,
                  color: post.viewerHasHearted
                      ? const Color(0xFFEF7C8E)
                      : const Color.fromRGBO(255, 255, 255, 0.55),
                  label: post.heartCount.toString(),
                  labelKey: const ValueKey<String>('post-heart-count'),
                ),
                _MetricAction(
                  icon: Icons.chat_bubble_outline,
                  onTap: onOpenComments,
                  color: const Color.fromRGBO(255, 255, 255, 0.55),
                  label: post.commentCount.toString(),
                  labelKey: const ValueKey<String>('post-comment-count'),
                ),
                if (canPassAlong || (showShareCount && post.shareCount > 0))
                  _MetricAction(
                    icon: Icons.redo,
                    onTap: onPassAlong,
                    color: const Color.fromRGBO(255, 255, 255, 0.55),
                    label: showShareCount ? post.shareCount.toString() : null,
                    labelKey: const ValueKey<String>('post-share-count'),
                  ),
                if (onPinPost != null)
                  _MetricAction(
                    icon: Icons.push_pin_outlined,
                    onTap: onPinPost,
                    color: const Color.fromRGBO(255, 255, 255, 0.55),
                  ),
              ];

              final expiry = Text(
                _expiryCopy(post.expiresAt, now).toLowerCase(),
                style: const TextStyle(
                  color: Color.fromRGBO(255, 255, 255, 0.38),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.right,
              );

              if (constraints.maxWidth < 380) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 18,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: actions,
                    ),
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerRight, child: expiry),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 18,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: actions,
                    ),
                  ),
                  const SizedBox(width: 12),
                  expiry,
                ],
              );
            },
          ),
        ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isPrimary
            ? const Color.fromRGBO(38, 190, 110, 0.12)
            : const Color.fromRGBO(255, 255, 255, 0.06),
        border: Border.all(
          color: isPrimary
              ? const Color.fromRGBO(38, 190, 110, 0.28)
              : const Color.fromRGBO(255, 255, 255, 0.10),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isPrimary
              ? const Color(0xFF24D36A)
              : const Color.fromRGBO(255, 255, 255, 0.82),
          fontSize: 12,
          fontWeight: FontWeight.w500,
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

  const _MetricAction({
    required this.icon,
    required this.onTap,
    required this.color,
    this.label,
    this.labelKey,
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
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: resolvedColor),
              if (label != null) ...[
                const SizedBox(width: 8),
                Text(
                  label!,
                  key: labelKey,
                  style: const TextStyle(
                    color: Color.fromRGBO(255, 255, 255, 0.52),
                    fontSize: 13,
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
