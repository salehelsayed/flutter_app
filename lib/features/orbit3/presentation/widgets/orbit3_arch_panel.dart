import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_group.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_inner_item.dart';

import '../../domain/orbit3_arch_layout.dart';

/// The compact "+N" ARCH chip that rides just above the Orbit3 One Circle once
/// the population outgrows the two inner orbits. Tapping it opens the
/// [Orbit3ArchPanel]. Sized to match the top-bar chips (166 R5).
class Orbit3ArchBar extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const Orbit3ArchBar({super.key, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _Orbit3GlassPill(
      pillKey: const ValueKey('orbit3-arch-overflow'),
      onTap: onTap,
      semanticLabel: '$count more people — tap to open',
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      children: [
        const Icon(Icons.people_alt_rounded, size: 14, color: _kArchAccent),
        const SizedBox(width: 6),
        Text(
          '+$count',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _kArchAccent,
          ),
        ),
      ],
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
        child: _Orbit3GlassPill(
          pillKey: const ValueKey('orbit3-arch-collapse'),
          onTap: onTap,
          semanticLabel: 'Collapse',
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          children: const [
            Icon(Icons.keyboard_arrow_up_rounded, size: 16, color: _kArchAccent),
            SizedBox(width: 5),
            Text(
              'Collapse',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _kArchAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The brand green used for the arch affordances' icons + text.
const Color _kArchAccent = Color(0xFF1ED760);

/// A glassy, accent-tinted pill with a soft green glow — the shared look for the
/// expand "+N" and the "Collapse" affordances so they read as a themed pair.
class _Orbit3GlassPill extends StatelessWidget {
  final Key pillKey;
  final VoidCallback onTap;
  final String semanticLabel;
  final List<Widget> children;
  final EdgeInsets padding;

  const _Orbit3GlassPill({
    required this.pillKey,
    required this.onTap,
    required this.semanticLabel,
    required this.children,
    required this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final readable = context.backgroundReadableColors;
    return GestureDetector(
      key: pillKey,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryAccent.withValues(alpha: 0.30),
                blurRadius: 16,
                spreadRadius: -2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                padding: padding,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primaryAccent.withValues(alpha: 0.24),
                      readable.glassSurface.withValues(alpha: 0.55),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primaryAccent.withValues(alpha: 0.55),
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: children),
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

  /// 0 = the row NEAREST the circle (bottom). Drives the bottom-up entrance.
  final int rowFromBottom;

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
    this.rowFromBottom = 0,
    this.onFriendTap,
    this.onGroupTap,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < rowItems.length && i < centres.length; i++) {
      final it = rowItems[i];
      final p = centres[i];
      final delayMs =
          orbit3ArchEntranceDelayMs(rowFromBottom: rowFromBottom, col: i);
      // Friends AND groups render with the SAME OrbitalAvatar chrome + the
      // rise-up bottom-up entrance (168 C2/C3); a group's content is a teal
      // group glyph instead of a peer photo.
      final Widget core = OrbitalAvatar(
        key: it.isGroup ? ValueKey('orbit3-arch-group-${it.id}') : null,
        peerId: it.isGroup ? it.id : it.friend!.peerId,
        size: avatar,
        globalIndex: rowOffset + i,
        motionEnabled: motionEnabled,
        riseUp: true,
        entranceDelayMs: delayMs,
        borderWidth: 1.0,
        borderColor: it.isGroup
            ? AppColors.tealAccent.withValues(alpha: 0.9)
            : readable.border.withValues(alpha: 0.2),
        semanticLabel:
            it.isGroup ? it.displayName : 'Open chat with ${it.displayName}',
        child: it.isGroup
            ? Container(
                color: AppColors.tealAccent.withValues(alpha: 0.9),
                alignment: Alignment.center,
                child: Icon(Icons.group_rounded,
                    size: avatar * 0.52, color: Colors.black87),
              )
            : null,
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

