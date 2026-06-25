import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_group.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_inner_item.dart';

/// The compact "+N" ARCH chip that rides just above the Orbit3 One Circle once
/// the population outgrows the two inner orbits. Tapping it opens the
/// [Orbit3ArchPanel]. Sized to match the top-bar chips (166 R5).
class Orbit3ArchBar extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const Orbit3ArchBar({super.key, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('orbit3-arch-overflow'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        label: '$count more people — tap to open',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.primaryAccent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primaryAccent.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.people_alt_rounded,
                size: 14,
                color: Color(0xFF1ED760),
              ),
              const SizedBox(width: 5),
              Text(
                '+$count',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1ED760),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small explicit COLLAPSE button — closes the expanded arches back to just
/// the inner circle (166 R4); pinned as a top-centre overlay by the screen (167).
class Orbit3ArchCollapsePill extends StatelessWidget {
  final BackgroundReadableColors readable;
  final VoidCallback onTap;
  const Orbit3ArchCollapsePill(
      {super.key, required this.readable, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: GestureDetector(
          key: const ValueKey('orbit3-arch-collapse'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Semantics(
            button: true,
            label: 'Collapse',
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: readable.glassSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: readable.glassBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 16,
                    color: readable.iconSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Collapse',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: readable.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One shallow-arc row of overflow members.
class Orbit3ArcRow extends StatelessWidget {
  final List<Offset> centres;
  final List<Orbit2InnerItem> rowItems;
  final int rowOffset;
  final double width;
  final double height;
  final double avatar;
  final BackgroundReadableColors readable;
  final bool motionEnabled;
  final ValueChanged<OrbitFriend>? onFriendTap;
  final ValueChanged<Orbit2Group>? onGroupTap;

  const Orbit3ArcRow({
    super.key,
    required this.centres,
    required this.rowItems,
    required this.rowOffset,
    required this.width,
    required this.height,
    required this.avatar,
    required this.readable,
    required this.motionEnabled,
    this.onFriendTap,
    this.onGroupTap,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < rowItems.length && i < centres.length; i++) {
      final it = rowItems[i];
      final p = centres[i];
      final globalIndex = rowOffset + i;
      final Widget core = it.isGroup
          ? _PanelGroupGlyph(size: avatar, readable: readable)
          : OrbitalAvatar(
              peerId: it.friend!.peerId,
              size: avatar,
              globalIndex: globalIndex,
              motionEnabled: motionEnabled,
              borderWidth: 1.0,
              borderColor: readable.border.withValues(alpha: 0.2),
              semanticLabel: 'Open chat with ${it.displayName}',
            );

      children.add(Positioned(
        // Centre the avatar on its arc point; y is negative at the dome's top.
        left: p.dx - avatar / 2,
        top: height / 2 + p.dy - avatar / 2,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: it.isGroup
              ? (onGroupTap == null ? null : () => onGroupTap!(it.group!))
              : (onFriendTap == null ? null : () => onFriendTap!(it.friend!)),
          child: SizedBox(width: avatar, height: avatar, child: core),
        ),
      ));
    }

    return SizedBox(
      width: width,
      height: height,
      child: Stack(clipBehavior: Clip.none, children: children),
    );
  }
}

/// A compact teal group disc for the panel (mirrors the One Circle group glyph).
class _PanelGroupGlyph extends StatelessWidget {
  final double size;
  final BackgroundReadableColors readable;
  const _PanelGroupGlyph({required this.size, required this.readable});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.tealAccent.withValues(alpha: 0.9),
        border: Border.all(
          color: readable.surfaceBase.withValues(alpha: 0.9),
          width: 1.2,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.group_rounded, size: size * 0.52, color: Colors.black87),
    );
  }
}
