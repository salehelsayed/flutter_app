import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_avatar.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_geometry_prefs.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/orbit_arc_layout.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'orbital_ring_painter.dart';
import 'orbital_avatar.dart';
import 'overflow_badge.dart';

/// Orbital visualization: dashed rings, center avatar, chat avatars, and (198)
/// concentric overflow arcs revealed by the badge toggle.
///
/// Ring 1 (inner): 5 items at 62px radius, 38px avatars.
/// Ring 2 (outer): next 8 items at 108px radius, 30px avatars, re-spread to 9
/// slots when overflowing so the badge takes the 9th.
///
/// 197 — the rings render the merged inner-circle union ([OrbitItem]).
/// 198 — [geometry] scales every seat; when [overflowExpanded] the overflow
/// members are seated on concentric arcs (same [OrbitalAvatar] species, 194
/// unread + 197 groups), and [onBadgeTap] toggles them. [labelsVisible] renders
/// a name under every node. All positions come from the pure `orbit_arc_layout`
/// engine so the painter and the seats stay in lock-step.
class OrbitalVisualization extends StatelessWidget {
  final String? userPeerId;
  final Uint8List? userAvatarBytes;
  final List<OrbitItem> items;
  final ValueChanged<OrbitFriend>? onFriendTap;
  final ValueChanged<OrbitGroup>? onGroupTap;

  /// 198 — the five sculpt knobs (defaults ⇒ pre-198 geometry, INV-6).
  final OrbitGeometryPrefs geometry;

  /// 198 — when true the overflow arcs are shown; the badge shows its chevron.
  final bool overflowExpanded;

  /// 198 — toggles [overflowExpanded] (wired by the host). The badge NEVER
  /// opens a chat.
  final VoidCallback? onBadgeTap;

  /// 198 — render a name label under every node (double-tap toggle).
  final bool labelsVisible;

  static const double _size = 320;
  static const double _center = _size / 2;
  static const double _minTapTargetSize = 48;

  const OrbitalVisualization({
    super.key,
    required this.userPeerId,
    this.userAvatarBytes,
    required this.items,
    this.onFriendTap,
    this.onGroupTap,
    this.geometry = OrbitGeometryPrefs.defaults,
    this.overflowExpanded = false,
    this.onBadgeTap,
    this.labelsVisible = false,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final innerBorderColor = readableColors.border.withValues(alpha: 0.20);
    final outerBorderColor = readableColors.border.withValues(alpha: 0.14);
    // 194/198 reduce-motion seam. Freezes the unread rotation AND (198) makes
    // the NEW arc entrance instant under OS reduce-motion (INV-7).
    final mediaQuery = MediaQuery.maybeOf(context);
    final motionEnabled = !((mediaQuery?.disableAnimations ?? false) ||
        (mediaQuery?.accessibleNavigation ?? false));
    final mirrored = Directionality.of(context) == TextDirection.rtl;

    final layout = computeOrbitLayout(
      memberCount: items.length,
      geometry: geometry,
      mirrored: mirrored,
    );

    // When expanded the arcs poke above the box; the circle slides down by the
    // overhang so the topmost arc clears the top margin (the host scroll view
    // compensates so it stays visually planted — Slice SCROLL).
    final overhang = overflowExpanded
        ? orbitArcOverhang(
            memberCount: items.length,
            geometry: geometry,
            centerY: _center,
          )
        : 0.0;
    final boxHeight = _size + overhang;
    final cx = _center;
    final cy = _center + overhang;

    // Painter arc rings (one per occupied arc) when expanded.
    final arcRings = <OrbitArcRing>[];
    if (overflowExpanded) {
      final seen = <int>{};
      for (final s in layout.seats) {
        if (s.kind != OrbitSeatKind.arc || !seen.add(s.arcIndex!)) continue;
        final r = orbitArcRadius(geometry, s.arcIndex!);
        arcRings.add(OrbitArcRing(
          radius: r,
          phiMax: orbitArcPhi(r, geometry.arcWrap),
          arcIndex: s.arcIndex!,
        ));
      }
    }

    final children = <Widget>[
      Positioned.fill(
        child: CustomPaint(
          painter: OrbitalRingPainter(
            center: Offset(cx, cy),
            ring1Radius: layout.ring1Radius,
            ring2Radius: layout.ring2Radius,
            arcs: arcRings,
          ),
        ),
      ),
      if (userPeerId != null)
        Positioned(
          left: cx - 24,
          top: cy - 24,
          child: UserAvatar(
            peerId: userPeerId,
            avatarBytes: userAvatarBytes,
            size: 48,
          ),
        ),
    ];

    // Seats — rings always; arcs only when expanded.
    for (final seat in layout.seats) {
      final isArc = seat.kind == OrbitSeatKind.arc;
      if (isArc && !overflowExpanded) continue;
      final item = items[seat.index];
      final tapTargetSize = _tapTargetSize(seat.avatarSize, item);
      final (borderWidth, borderColor) = switch (seat.kind) {
        OrbitSeatKind.ring1 => (1.5, innerBorderColor),
        OrbitSeatKind.ring2 => (1.0, outerBorderColor),
        OrbitSeatKind.arc => (1.0, outerBorderColor),
      };
      children.add(Positioned(
        left: cx + seat.dx - tapTargetSize / 2,
        top: cy + seat.dy - tapTargetSize / 2,
        child: _buildNode(
          item,
          avatarSize: seat.avatarSize,
          globalIndex: seat.index,
          borderWidth: borderWidth,
          borderColor: borderColor,
          l10n: l10n,
          unreadMotionEnabled: motionEnabled,
          // Ring entrance keeps the pre-198 stagger; arc entrance uses the
          // layout stagger and honors reduce-motion (INV-7).
          entranceDelayMs: isArc ? seat.entranceDelayMs : null,
          entranceMotionEnabled: isArc ? motionEnabled : true,
        ),
      ));
      if (labelsVisible) {
        children.add(_buildLabel(item, seat, cx, cy, readableColors));
      }
    }

    // Overflow badge (present whenever the population overflows). Its box is
    // 44px when interactive (−8px inset around the 28px visual) else 28px.
    if (layout.badge != null) {
      final badge = layout.badge!;
      final badgeHalf = onBadgeTap != null ? 22.0 : 14.0;
      children.add(Positioned(
        left: cx + badge.dx - badgeHalf,
        top: cy + badge.dy - badgeHalf,
        child: OverflowBadge(
          count: badge.overflowCount,
          expanded: overflowExpanded,
          onTap: onBadgeTap,
        ),
      ));
    }

    return Column(
      children: [
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
        SizedBox(
          width: _size,
          height: boxHeight,
          child: Stack(clipBehavior: Clip.none, children: children),
        ),
      ],
    );
  }

  /// Builds a single node from an [OrbitItem]: a 1:1 friend avatar or a group
  /// node (group image/initials + unread indicator). Arc nodes are the SAME
  /// species as ring nodes (168 C2 / 198 TC-10/11).
  Widget _buildNode(
    OrbitItem item, {
    required double avatarSize,
    required int globalIndex,
    required double borderWidth,
    required Color borderColor,
    required AppLocalizations l10n,
    required bool unreadMotionEnabled,
    int? entranceDelayMs,
    bool entranceMotionEnabled = true,
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
          entranceDelayMs: entranceDelayMs,
          motionEnabled: entranceMotionEnabled,
        );
      case OrbitGroupItem(:final group):
        return OrbitalAvatar(
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
          entranceDelayMs: entranceDelayMs,
          motionEnabled: entranceMotionEnabled,
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

  /// A name label under a node (198 double-tap labels). Arc labels alternate a
  /// small vertical offset ([OrbitSeat.staggerParity]) so neighbours don't
  /// collide; ring labels never stagger.
  Widget _buildLabel(
    OrbitItem item,
    OrbitSeat seat,
    double cx,
    double cy,
    BackgroundReadableColors readableColors,
  ) {
    const labelWidth = 72.0;
    final stagger = seat.staggerParity * 12.0;
    return Positioned(
      left: cx + seat.dx - labelWidth / 2,
      top: cy + seat.dy + seat.avatarSize / 2 + 2 + stagger,
      width: labelWidth,
      child: IgnorePointer(
        child: Text(
          _displayName(item),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9,
            color: readableColors.textMuted,
            height: 1,
          ),
        ),
      ),
    );
  }

  String _displayName(OrbitItem item) => switch (item) {
        OrbitFriendItem(:final friend) => friend.username,
        OrbitGroupItem(:final group) => group.name,
      };

  bool _itemHasTap(OrbitItem item) => switch (item) {
        OrbitFriendItem() => onFriendTap != null,
        OrbitGroupItem() => onGroupTap != null,
      };

  double _tapTargetSize(double avatarSize, OrbitItem item) {
    if (!_itemHasTap(item) || avatarSize >= _minTapTargetSize) {
      return avatarSize;
    }
    return _minTapTargetSize;
  }
}
