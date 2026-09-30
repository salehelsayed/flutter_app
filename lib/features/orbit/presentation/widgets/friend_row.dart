import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/feed/domain/utils/format_message_time.dart';
import 'package:flutter_app/features/feed/presentation/widgets/unread_count_badge.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_media_preview_label.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Glassmorphic tappable friend card for the friends list.
class FriendRow extends StatelessWidget {
  final OrbitFriend friend;
  final bool showInnerCircleBadge;
  final bool hideUnreadBadge;
  final VoidCallback onTap;

  /// Invoked when the avatar specifically is tapped (opens the contact
  /// profile). Falls back to the row's [onTap] when null.
  final VoidCallback? onAvatarTap;

  const FriendRow({
    super.key,
    required this.friend,
    required this.onTap,
    this.onAvatarTap,
    this.showInnerCircleBadge = false,
    this.hideUnreadBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    // 409: a call can be the newest thing here, so the row's time follows the
    // newest activity rather than the newest message.
    final activityAt = friend.lastActivityAt;
    final relativeTime = activityAt != null
        ? formatRelativeTime(activityAt)
        : '';
    // Resolve the preview: caption wins; else a localized media label
    // ("Voice message" / "Photo" / "2 photos" …); else the deleted placeholder.
    // Empty-but-present text on a media-only message no longer renders Text('').
    final previewText = orbitMediaPreviewLabel(
      l10n: l10n,
      caption: friend.lastActivity,
      media: friend.latestMedia,
      call: friend.latestCall,
      isDeleted: friend.isLatestDeleted,
    );
    final previewDirection = previewText.isNotEmpty
        ? detectTextDirection(previewText)
        : TextDirection.ltr;

    return Semantics(
      identifier: 'orbit.contact.${friend.peerId}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: readableColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(16),
            // 248 — decorative row outline: soft surfaceBorder on light, unchanged
            // (surfaceBorder == border) on dark.
            border: Border.all(color: readableColors.surfaceBorder),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const titleStyle = TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              );
              const metaStyle = TextStyle(fontSize: 12);
              double textWidth(String text, TextStyle style) {
                final painter = TextPainter(
                  text: TextSpan(
                    text: text,
                    style: DefaultTextStyle.of(context).style.merge(style),
                  ),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout();
                final width = painter.width;
                painter.dispose();
                return width;
              }

              // Retain the horizontal card when it can show a useful name prefix.
              // Otherwise give name, badge and metadata separate bounded lines.
              final prefix = friend.username.characters.take(4).toString();
              final nameWidth = textWidth(
                prefix.length < friend.username.length ? '$prefix…' : prefix,
                titleStyle,
              );
              final badgeWidth = showInnerCircleBadge
                  ? textWidth(
                          l10n.orbit_inner_circle_badge,
                          const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ) +
                        22
                  : 0.0;
              final countWidth = !hideUnreadBadge && friend.unreadCount > 0
                  ? textWidth(
                          friend.unreadCount > 99
                              ? '99+'
                              : '${friend.unreadCount}',
                          const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ) +
                        12
                  : 16.0;
              final timeWidth = textWidth(relativeTime, metaStyle);
              final metaWidth = timeWidth > countWidth ? timeWidth : countWidth;
              final stacked =
                  constraints.maxWidth <
                  48 + 14 + nameWidth + badgeWidth + 10 + metaWidth;
              final title = Text(
                friend.username,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: readableColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              );
              final badge = Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: readableColors.isLightSurface
                      ? const Color(0xFFE5F4EA)
                      : const Color(0x261DB954),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  l10n.orbit_inner_circle_badge,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: Color(0xCC1DB954), // rgba(29,185,84,0.8)
                  ),
                ),
              );
              final time = Text(
                relativeTime,
                style: TextStyle(fontSize: 12, color: readableColors.textMuted),
              );
              final trailing = (!hideUnreadBadge && friend.unreadCount > 0)
                  ? UnreadCountBadge(count: friend.unreadCount)
                  : Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: readableColors.iconMuted,
                    );

              return Row(
                children: [
                  GestureDetector(
                    onTap: onAvatarTap ?? onTap,
                    behavior: HitTestBehavior.opaque,
                    child: UserAvatar(peerId: friend.peerId, size: 48),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (stacked) ...[
                          title,
                          if (showInnerCircleBadge) ...[
                            const SizedBox(height: 4),
                            badge,
                          ],
                        ] else
                          Row(
                            children: [
                              Flexible(child: title),
                              if (showInnerCircleBadge) ...[
                                const SizedBox(width: 8),
                                badge,
                              ],
                            ],
                          ),
                        if (previewText.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            previewText,
                            textDirection: previewDirection,
                            style: TextStyle(
                              fontSize: 12,
                              color: readableColors.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (stacked) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (relativeTime.isNotEmpty)
                                Expanded(child: time)
                              else
                                const Spacer(),
                              const SizedBox(width: 10),
                              trailing,
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!stacked) ...[
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (relativeTime.isNotEmpty) time,
                        const SizedBox(height: 4),
                        trailing,
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Animated wrapper for friend rows with staggered slide-up entrance.
class AnimatedFriendRow extends StatefulWidget {
  final int index;
  final Widget child;

  const AnimatedFriendRow({
    super.key,
    required this.index,
    required this.child,
  });

  @override
  State<AnimatedFriendRow> createState() => _AnimatedFriendRowState();
}

class _AnimatedFriendRowState extends State<AnimatedFriendRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  bool _entranceScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.ease);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(_fadeAnimation);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entranceScheduled) return;
    _entranceScheduled = true;
    // 202 INV-202-6: honor OS reduce-motion (jump to the end, no ticker) and
    // clamp the stagger so a deep-list row is never invisible for seconds on a
    // fling — index*20ms was unbounded (index 100 → 2s).
    final mediaQuery = MediaQuery.maybeOf(context);
    final reduceMotion =
        (mediaQuery?.disableAnimations ?? false) ||
        (mediaQuery?.accessibleNavigation ?? false);
    if (reduceMotion) {
      _controller.value = 1.0;
      return;
    }
    final delayMs = math.min(widget.index, 12) * 20;
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(position: _slideAnimation, child: widget.child),
    );
  }
}
