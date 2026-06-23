import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_group.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_inner_item.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../domain/orbit3_one_circle_layout.dart';

/// Width budget for a member's name label (kept under the ring arc spacing so
/// adjacent labels don't collide).
const double _kLabelW = 56;

/// Orbit3's self-contained "One Circle". Members fill fixed Orbit-parity rings
/// SEQUENTIALLY: ring 1 (5 @38px) fills first, then ring 2 (8 @30px) appears and
/// fills; once both are full an expand arrow reveals ring 3 (and beyond, @26px),
/// growing the circle outward.
///
/// Two things set it apart from Orbit2's inner circle, both per the Orbit3 spec:
///   1. A circle-wide [onToggleNames] double-tap — double-tapping anywhere over
///      the rings/avatars toggles the name labels, while a single tap on a
///      member still opens its chat (see the ancestor-detector note at the build
///      return).
///   2. Progressive rings sized to match the real Orbit screen (see
///      [computeOrbit3RingLayout]).
///
/// Deliberately owns its small painter / label / group-glyph / expand-node so
/// tweaks here never regress the shipped Orbit2 prototype.
class Orbit3OneCircle extends StatelessWidget {
  final String? userPeerId;
  final Uint8List? userAvatarBytes;
  final List<Orbit2InnerItem> items;
  final bool expanded;
  final bool namesVisible;
  final bool motionEnabled;
  final String searchQuery;
  final VoidCallback? onToggleNames;
  final VoidCallback? onToggleExpand;
  final ValueChanged<OrbitFriend>? onFriendTap;
  final ValueChanged<Orbit2Group>? onGroupTap;

  const Orbit3OneCircle({
    super.key,
    required this.userPeerId,
    this.userAvatarBytes,
    required this.items,
    this.expanded = false,
    this.namesVisible = true,
    this.motionEnabled = true,
    this.searchQuery = '',
    this.onToggleNames,
    this.onToggleExpand,
    this.onFriendTap,
    this.onGroupTap,
  });

  Offset _pos(int index, int count, double radius, int ring) {
    if (count == 0) return Offset.zero;
    final stagger = ring * 15;
    final angle = (index * 360 / count + stagger - 90) * (pi / 180);
    return Offset(cos(angle) * radius, sin(angle) * radius);
  }

  @override
  Widget build(BuildContext context) {
    final readable = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final names = namesVisible;

    final layout =
        computeOrbit3RingLayout(count: items.length, expanded: expanded);
    final counts = layout.counts;
    final radii = layout.radii;
    final avatarSizes = layout.avatarSizes;
    final box = layout.boxSize;
    final c = box / 2;

    // The expand/collapse node rides the outermost VISIBLE ring (Orbit2 style),
    // occupying one reserved slot so it never lands on a member.
    final outerRing = counts.isEmpty ? 0 : counts.length - 1;
    final showExpand = !expanded && layout.hasHidden;
    final showCollapse = expanded && layout.totalRings > kOrbit3CollapsedRings;
    final hasNode = showExpand || showCollapse;

    final q = searchQuery.trim().toLowerCase();
    final searching = q.isNotEmpty;
    bool matches(Orbit2InnerItem it) => it.displayName.toLowerCase().contains(q);

    List<Widget> slotFor(
        Orbit2InnerItem it, double av, int globalIndex, Offset p) {
      final t = (onFriendTap != null || onGroupTap != null) && av < 48
          ? 48.0
          : av;
      final isMatch = searching && matches(it);
      final isDim = searching && !matches(it);

      final Widget core = it.isGroup
          ? KeyedSubtree(
              key: ValueKey('orbit3-inner-group-${it.id}'),
              child: _Orbit3GroupGlyph(size: av, readable: readable),
            )
          : OrbitalAvatar(
              peerId: it.friend!.peerId,
              size: av,
              globalIndex: globalIndex,
              borderWidth: 1.0,
              borderColor: readable.border.withValues(alpha: 0.18),
              semanticLabel: 'Open chat with ${it.displayName}',
              motionEnabled: motionEnabled,
            );

      Widget avatar = core;
      if (isMatch) {
        avatar = Container(
          key: ValueKey('inner-glow-${it.id}'),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryAccent.withValues(alpha: 0.65),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: core,
        );
      }

      final out = <Widget>[
        Positioned(
          left: c + p.dx - t / 2,
          top: c + p.dy - t / 2,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: it.isGroup
                ? (onGroupTap == null ? null : () => onGroupTap!(it.group!))
                : (onFriendTap == null ? null : () => onFriendTap!(it.friend!)),
            child: SizedBox(
              width: t,
              height: t,
              child: Center(
                child: Opacity(
                  opacity: isDim ? 0.28 : 1.0,
                  child: avatar,
                ),
              ),
            ),
          ),
        ),
      ];

      if (names || isMatch) {
        final lp = Offset(p.dx, p.dy + av / 2 + 7);
        out.add(Positioned(
          left: (c + lp.dx - _kLabelW / 2).clamp(0.0, box - _kLabelW),
          top: (c + lp.dy - 7).clamp(0.0, box - 14),
          width: _kLabelW,
          child: IgnorePointer(
            child: Opacity(
              opacity: isDim ? 0.28 : 1.0,
              child: _Orbit3NameLabel(name: it.displayName, readable: readable),
            ),
          ),
        ));
      }
      return out;
    }

    final children = <Widget>[
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(painter: _Orbit3RingPainter(radii)),
        ),
      ),
      if (userPeerId != null)
        Positioned(
          left: c - layout.centerSize / 2,
          top: c - layout.centerSize / 2,
          child: IgnorePointer(
            child: UserAvatar(
              peerId: userPeerId,
              avatarBytes: userAvatarBytes,
              size: layout.centerSize,
            ),
          ),
        ),
      if (userPeerId != null && names)
        Positioned(
          left: c - _kLabelW / 2,
          top: c + layout.centerSize / 2 + 3,
          width: _kLabelW,
          child: IgnorePointer(
            child: _Orbit3NameLabel(name: l10n.orbit2_you, readable: readable),
          ),
        ),
    ];

    var idx = 0;
    for (var k = 0; k < counts.length; k++) {
      final m = counts[k];
      // Reserve a slot on the outermost visible ring for the expand/collapse node
      // so the members spread around it.
      final slotCount = (k == outerRing && hasNode) ? m + 1 : m;
      for (var i = 0; i < m; i++) {
        final p = _pos(i, slotCount, radii[k], k);
        children.addAll(slotFor(items[idx], avatarSizes[k], idx, p));
        idx++;
      }
    }

    if (hasNode && radii.isNotEmpty) {
      final m = counts[outerRing];
      final np = _pos(m, m + 1, radii[outerRing], outerRing);
      children.add(Positioned(
        left: c + np.dx - 15,
        top: c + np.dy - 15,
        child: GestureDetector(
          key: const ValueKey('orbit3-expand-toggle'),
          onTap: onToggleExpand,
          behavior: HitTestBehavior.opaque,
          child: _Orbit3ExpandNode(
            expanded: expanded,
            hiddenCount: layout.hiddenCount,
            readable: readable,
            semanticLabel: showCollapse
                ? l10n.orbit2_show_less
                : '+${layout.hiddenCount}',
          ),
        ),
      ));
    }

    // A double-tap ANYWHERE over the circle toggles names — the Orbit3 headline.
    // The detector is an ANCESTOR of every member (not a sibling behind the
    // circle, as Orbit2 does it). That is deliberate: a behind-the-circle detector
    // only catches double-taps over EMPTY space (members occlude it), which is
    // exactly the "double-tap on the rings/avatars doesn't toggle" bug Orbit3
    // exists to fix. As an ancestor, the double-tap recognizer shares the gesture
    // arena with each member's tap, so a double-tap over a member resolves to the
    // toggle while a single tap still opens that member's chat.
    //
    // Tradeoff: a member's single-tap (open chat) waits one kDoubleTapTimeout
    // (~300ms) before firing — intrinsic to supporting double-tap over avatars,
    // acceptable for this prototype, and locked by a screen test.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: onToggleNames,
      child: SizedBox(
        width: box,
        height: box,
        child: Stack(clipBehavior: Clip.none, children: children),
      ),
    );
  }
}

/// A tiny, no-pill name label for a member, sitting just under the avatar. A
/// faint shadow keeps it legible over the orbits.
class _Orbit3NameLabel extends StatelessWidget {
  final String name;
  final BackgroundReadableColors readable;
  const _Orbit3NameLabel({required this.name, required this.readable});

  @override
  Widget build(BuildContext context) {
    return Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 9.5,
        height: 1.05,
        fontWeight: FontWeight.w600,
        color: readable.textPrimary,
        shadows: const [Shadow(color: Colors.black54, blurRadius: 3)],
      ),
    );
  }
}

/// A compact, legible group node: a teal disc with a group glyph (deliberately
/// NOT a mini orbit, illegible at ring sizes), under a distinct key namespace.
class _Orbit3GroupGlyph extends StatelessWidget {
  final double size;
  final BackgroundReadableColors readable;
  const _Orbit3GroupGlyph({required this.size, required this.readable});

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
        boxShadow: [
          BoxShadow(
            color: AppColors.tealAccent.withValues(alpha: 0.3),
            blurRadius: 8,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(Icons.group_rounded, size: size * 0.52, color: Colors.black87),
    );
  }
}

/// A small circular node on the outer orbit: a down-arrow (+N hidden) to reveal
/// the next rings, or an up-arrow to collapse back to two rings.
class _Orbit3ExpandNode extends StatelessWidget {
  final bool expanded;
  final int hiddenCount;
  final BackgroundReadableColors readable;
  final String semanticLabel;

  const _Orbit3ExpandNode({
    required this.expanded,
    required this.hiddenCount,
    required this.readable,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: ClipOval(
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: readable.glassSurface,
            border: Border.all(
              color: AppColors.primaryAccent.withValues(alpha: 0.65),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryAccent.withValues(alpha: 0.28),
                blurRadius: 10,
              ),
            ],
          ),
          child: expanded
              ? const Icon(Icons.keyboard_arrow_up_rounded,
                  size: 18, color: Color(0xFF1ED760))
              : Text(
                  '+$hiddenCount',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1ED760),
                  ),
                ),
        ),
      ),
    );
  }
}

class _Orbit3RingPainter extends CustomPainter {
  final List<double> radii;
  const _Orbit3RingPainter(this.radii);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (final r in radii) {
      final glow = Paint()
        ..color = const Color(0x1481E6D9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(center, r, glow);

      final paint = Paint()
        ..color = const Color(0x4081E6D9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      const dash = 8.0;
      const gap = 4.0;
      final circ = 2 * pi * r;
      final count = (circ / (dash + gap)).floor();
      for (var i = 0; i < count; i++) {
        final start = (i * (dash + gap) / circ) * 2 * pi;
        final sweep = (dash / circ) * 2 * pi;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: r),
          start,
          sweep,
          false,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Orbit3RingPainter old) =>
      !listEquals(old.radii, radii);
}
