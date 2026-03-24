import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/feed/domain/utils/format_message_time.dart';
import 'package:flutter_app/features/feed/presentation/widgets/unread_count_badge.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';

/// Glassmorphic tappable friend card for the friends list.
class FriendRow extends StatelessWidget {
  final OrbitFriend friend;
  final bool showInnerCircleBadge;
  final bool hideUnreadBadge;
  final VoidCallback onTap;

  const FriendRow({
    super.key,
    required this.friend,
    required this.onTap,
    this.showInnerCircleBadge = false,
    this.hideUnreadBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final relativeTime = friend.lastMessageTimestamp != null
        ? formatRelativeTime(friend.lastMessageTimestamp!)
        : '';
    final lastActivityDirection = friend.lastActivity != null
        ? detectTextDirection(friend.lastActivity!)
        : TextDirection.ltr;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0x14FFFFFF), // rgba(255,255,255,0.08)
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0x1FFFFFFF), // rgba(255,255,255,0.12)
          ),
        ),
        child: Row(
          children: [
            // Avatar
            UserAvatar(peerId: friend.peerId, size: 48),
            const SizedBox(width: 14),

            // Info column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          friend.username,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xF2FFFFFF), // rgba(255,255,255,0.95)
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (showInnerCircleBadge) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x261DB954), // rgba(29,185,84,0.15)
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Inner Circle',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                              color: Color(0xCC1DB954), // rgba(29,185,84,0.8)
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (friend.lastActivity != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      friend.lastActivity!,
                      textDirection: lastActivityDirection,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0x99FFFFFF), // rgba(255,255,255,0.6)
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // Meta column
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (relativeTime.isNotEmpty)
                  Text(
                    relativeTime,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0x66FFFFFF), // rgba(255,255,255,0.4)
                    ),
                  ),
                const SizedBox(height: 4),
                if (!hideUnreadBadge && friend.unreadCount > 0)
                  UnreadCountBadge(count: friend.unreadCount)
                else
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: Color(0x66FFFFFF),
                  ),
              ],
            ),
          ],
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

    Future.delayed(
      Duration(milliseconds: widget.index * 20),
      () {
        if (mounted) _controller.forward();
      },
    );
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
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}
