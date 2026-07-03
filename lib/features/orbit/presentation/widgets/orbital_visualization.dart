import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_avatar.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'orbital_ring_painter.dart';
import 'orbital_avatar.dart';
import 'overflow_badge.dart';

/// 320x320 orbital visualization: dashed rings, center avatar, chat avatars.
///
/// Ring 1 (inner): top 5 items at 62px radius, 38px avatars.
/// Ring 2 (outer): next 8 items at 108px radius, 30px avatars.
/// Overflow badge if items > 13.
///
/// 197 — the rings render the merged inner-circle union ([OrbitItem]): 1:1
/// friends and group chats interleaved by recency. Friend nodes route taps to
/// [onFriendTap]; group nodes render their [GroupAvatar] (image or initials) +
/// unread indicator and route taps to [onGroupTap].
class OrbitalVisualization extends StatelessWidget {
  final String? userPeerId;
  final Uint8List? userAvatarBytes;
  final List<OrbitItem> items;
  final ValueChanged<OrbitFriend>? onFriendTap;
  final ValueChanged<OrbitGroup>? onGroupTap;

  static const double _size = 320;
  static const double _center = _size / 2;
  static const double _ring1Radius = 62;
  static const double _ring2Radius = 108;
  static const int _ring1Count = 5;
  static const int _ring2Count = 8;
  static const double _minTapTargetSize = 48;

  const OrbitalVisualization({
    super.key,
    required this.userPeerId,
    this.userAvatarBytes,
    required this.items,
    this.onFriendTap,
    this.onGroupTap,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final innerBorderColor = readableColors.border.withValues(alpha: 0.20);
    final outerBorderColor = readableColors.border.withValues(alpha: 0.14);
    // 194: reduce-motion seam (cosmic_background convention). Threaded into the
    // unread indicator so its rotation freezes under OS reduce-motion while the
    // ring + satellites stay statically visible.
    final mediaQuery = MediaQuery.maybeOf(context);
    final unreadMotionEnabled = !((mediaQuery?.disableAnimations ?? false) ||
        (mediaQuery?.accessibleNavigation ?? false));
    final ring1Items = items.take(_ring1Count).toList();
    final ring2Items = items.skip(_ring1Count).take(_ring2Count).toList();
    final overflowCount = items.length > 13 ? items.length - 13 : 0;

    return Column(
      children: [
        // Section title
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Text(
            l10n.orbit_inner_circle_title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: readableColors.textMuted,
              letterSpacing: 1,
            ),
          ),
        ),

        // Orbital container
        SizedBox(
          width: _size,
          height: _size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Dashed rings
              Positioned.fill(
                child: CustomPaint(painter: OrbitalRingPainter()),
              ),

              // Center avatar
              if (userPeerId != null)
                Positioned(
                  left: _center - 24,
                  top: _center - 24,
                  child: UserAvatar(
                    peerId: userPeerId,
                    avatarBytes: userAvatarBytes,
                    size: 48,
                  ),
                ),

              // Ring 1 items (inner orbit)
              ...List.generate(ring1Items.length, (i) {
                final item = ring1Items[i];
                const avatarSize = 38.0;
                final tapTargetSize = _tapTargetSize(avatarSize, item);
                final pos = _positionOnRing(
                  index: i,
                  count: ring1Items.length,
                  radius: _ring1Radius,
                  ringIndex: 0,
                );
                return Positioned(
                  left: _center + pos.dx - tapTargetSize / 2,
                  top: _center + pos.dy - tapTargetSize / 2,
                  child: _buildNode(
                    item,
                    avatarSize: avatarSize,
                    globalIndex: i,
                    borderWidth: 1.5,
                    borderColor: innerBorderColor,
                    l10n: l10n,
                    unreadMotionEnabled: unreadMotionEnabled,
                  ),
                );
              }),

              // Ring 2 items (outer orbit)
              ...List.generate(ring2Items.length, (i) {
                final item = ring2Items[i];
                const avatarSize = 30.0;
                final tapTargetSize = _tapTargetSize(avatarSize, item);
                final pos = _positionOnRing(
                  index: i,
                  count: ring2Items.length,
                  radius: _ring2Radius,
                  ringIndex: 1,
                );
                return Positioned(
                  left: _center + pos.dx - tapTargetSize / 2,
                  top: _center + pos.dy - tapTargetSize / 2,
                  child: _buildNode(
                    item,
                    avatarSize: avatarSize,
                    globalIndex: _ring1Count + i,
                    borderWidth: 1,
                    borderColor: outerBorderColor,
                    l10n: l10n,
                    unreadMotionEnabled: unreadMotionEnabled,
                  ),
                );
              }),

              // Overflow badge
              if (overflowCount > 0) ...[
                () {
                  final badgePos = _positionOnRing(
                    index: ring2Items.length,
                    count: ring2Items.length + 1,
                    radius: _ring2Radius,
                    ringIndex: 1,
                  );
                  return Positioned(
                    left: _center + badgePos.dx - 14,
                    top: _center + badgePos.dy - 14,
                    child: OverflowBadge(count: overflowCount),
                  );
                }(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Builds a single ring node from an [OrbitItem]: a 1:1 friend avatar or a
  /// group node (group image/initials + unread indicator), routing taps to the
  /// matching callback. Group nodes pass their [GroupAvatar] as the node
  /// [OrbitalAvatar.child] (168 C2) so they read as the same bordered circle +
  /// entrance + unread overlay as friend nodes.
  Widget _buildNode(
    OrbitItem item, {
    required double avatarSize,
    required int globalIndex,
    required double borderWidth,
    required Color borderColor,
    required AppLocalizations l10n,
    required bool unreadMotionEnabled,
  }) {
    switch (item) {
      case OrbitFriendItem(:final friend):
        return OrbitalAvatar(
          peerId: friend.peerId,
          size: avatarSize,
          globalIndex: globalIndex,
          borderWidth: borderWidth,
          borderColor: borderColor,
          onTap: onFriendTap == null ? null : () => onFriendTap!(friend),
          semanticLabel: friend.unreadCount > 0
              ? l10n.orbit_node_unread_open_chat(
                  friend.username,
                  friend.unreadCount,
                )
              : 'Open chat with ${friend.username}',
          unreadCount: friend.unreadCount,
          unreadMotionEnabled: unreadMotionEnabled,
        );
      case OrbitGroupItem(:final group):
        return OrbitalAvatar(
          // Non-null placeholder — unused for rendering when [child] is set, but
          // it keys the entrance/semantics, so pass the real groupId (not '').
          peerId: group.groupId,
          size: avatarSize,
          globalIndex: globalIndex,
          borderWidth: borderWidth,
          borderColor: borderColor,
          onTap: onGroupTap == null ? null : () => onGroupTap!(group),
          semanticLabel: group.unreadCount > 0
              ? l10n.orbit_node_unread_open_group(
                  group.name,
                  group.unreadCount,
                )
              : l10n.orbit_node_open_group(group.name),
          unreadCount: group.unreadCount,
          unreadMotionEnabled: unreadMotionEnabled,
          // Circular borderRadius matches the node's ClipOval to avoid a
          // doubled/mismatched group border on the ring.
          child: GroupAvatar(
            groupId: group.groupId,
            name: group.name,
            avatarPath: group.group.avatarPath,
            size: avatarSize - borderWidth * 2,
            borderRadius: BorderRadius.circular(avatarSize),
            cacheBustKey: group.group.lastMetadataEventAt?.toIso8601String(),
          ),
        );
    }
  }

  /// Whether this node is tappable (its matching callback is wired), so its
  /// positioned box reserves the 48px minimum tap target — mirroring
  /// [OrbitalAvatar]'s own per-node tap-target math.
  bool _itemHasTap(OrbitItem item) => switch (item) {
    OrbitFriendItem() => onFriendTap != null,
    OrbitGroupItem() => onGroupTap != null,
  };

  /// Calculates position on a ring using the spec's trigonometric formula.
  Offset _positionOnRing({
    required int index,
    required int count,
    required double radius,
    required int ringIndex,
  }) {
    if (count == 0) return Offset.zero;
    final offset = ringIndex * 15; // degrees stagger per ring
    final angle = (index * 360 / count + offset - 90) * (pi / 180);
    return Offset(cos(angle) * radius, sin(angle) * radius);
  }

  double _tapTargetSize(double avatarSize, OrbitItem item) {
    if (!_itemHasTap(item) || avatarSize >= _minTapTargetSize) {
      return avatarSize;
    }
    return _minTapTargetSize;
  }
}
