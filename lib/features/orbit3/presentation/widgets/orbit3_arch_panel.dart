import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_group.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_inner_item.dart';

import '../../domain/orbit3_arch_layout.dart';

/// Comfortable base avatar diameter for an arch-panel member, before the live
/// [Orbit3ArchPanel.avatarScale] multiplier (a touch under the circle's 38 so
/// the arc rows read as a tighter band).
const double _kArchPanelAvatar = 36;

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

/// The arch overflow panel: a scroll-up layer of continuous shallow-arc rows of
/// the overflow members (~8 per arc), with a "MORE" header that closes it.
///
/// Visuals-only prototype: members are the inner-circle items beyond the first
/// [kOrbit3InnerSeats]. Tapping a member opens its (mock) chat.
class Orbit3ArchPanel extends StatelessWidget {
  final List<Orbit2InnerItem> items;
  final double avatarScale;
  final bool motionEnabled;
  final VoidCallback onClose;
  final ValueChanged<OrbitFriend>? onFriendTap;
  final ValueChanged<Orbit2Group>? onGroupTap;

  const Orbit3ArchPanel({
    super.key,
    required this.items,
    this.avatarScale = 1.0,
    this.motionEnabled = true,
    required this.onClose,
    this.onFriendTap,
    this.onGroupTap,
  });

  @override
  Widget build(BuildContext context) {
    final readable = context.backgroundReadableColors;

    // Transparent on purpose: the arcs float ABOVE the inner circle on the same
    // starfield, with the circle still visible (and tappable) below.
    return GestureDetector(
      key: const ValueKey('orbit3-arch-panel'),
      behavior: HitTestBehavior.opaque,
      onTap: onClose, // tap empty space above the circle to dismiss
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width =
              constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
          final count = items.length;

          // COMFORTABLE sizing (no compression): a fixed avatar size; perRow
          // from the width. Only the rows that FIT show; the rest SCROLL — the
          // band never grows into the circle (166 R1).
          final base =
              (_kArchPanelAvatar * avatarScale).clamp(20.0, 60.0).toDouble();
          final int perRow =
              (width / (base + 6)).floor().clamp(6, 11).toInt();
          final rowHeight = base + 14.0;
          final dip = (base * 0.32).clamp(7.0, 13.0).toDouble();

          final layout = computeOrbit3ArchArcs(
            count: count,
            width: width,
            avatar: base,
            perRow: perRow,
            dip: dip,
          );
          return Column(
            children: [
              _CollapsePill(readable: readable, onTap: onClose),
              Expanded(
                // Bottom-anchored, LAZY list: row 0 (nearest the circle) sits at
                // the bottom; scroll UP for farther rows. Only visible rows build,
                // so the arcs cap to what fits and the rest scroll into view.
                child: ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                  itemCount: layout.rows.length,
                  itemBuilder: (context, r) => _ArcRow(
                    key: ValueKey('orbit3-arch-arc-row-$r'),
                    centres: layout.rows[r],
                    rowItems: items
                        .skip(r * perRow)
                        .take(layout.rows[r].length)
                        .toList(),
                    rowOffset: r * perRow,
                    width: width,
                    height: rowHeight,
                    avatar: base,
                    readable: readable,
                    motionEnabled: motionEnabled,
                    onFriendTap: onFriendTap,
                    onGroupTap: onGroupTap,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A small explicit COLLAPSE button at the top of the panel — closes the arcs
/// back to just the inner circle (166 R4).
class _CollapsePill extends StatelessWidget {
  final BackgroundReadableColors readable;
  final VoidCallback onTap;
  const _CollapsePill({required this.readable, required this.onTap});

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
class _ArcRow extends StatelessWidget {
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

  const _ArcRow({
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
