import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../domain/models/orbit2_group.dart';
import '../../domain/models/orbit2_inner_item.dart';

/// Width budget for an inner-circle member's name label (kept under the ring
/// arc spacing so adjacent labels don't collide).
const double _kInnerLabelW = 56;

/// Title-less, sized Inner Circle for the unified Orbit2 canvas.
///
/// Dotted orbits are drawn at the avatar-ring radii, centred on the box. When
/// [expanded] it reveals a 3rd ring (and a small collapse node). Members can be
/// tapped (chat) or long-press-dragged OUT to remove them. A member whose name
/// matches [searchQuery] glows.
class Orbit2InnerCircle extends StatelessWidget {
  final String? userPeerId;
  final Uint8List? userAvatarBytes;
  final List<Orbit2InnerItem> items;
  final double size;
  final bool expanded;
  /// "One Circle" prototype: pack EVERY member into concentric rings that grow
  /// to fit them all — no "+N" overflow, no expand node, no scattered canvas.
  final bool unified;
  final bool namesVisible;
  final bool motionEnabled;
  final bool carryActive;
  final bool highlighted;
  final String? dropLabel;
  final String? carriedOutId;
  final String searchQuery;
  final bool manageMode;
  final VoidCallback? onOverflowTap;
  final ValueChanged<OrbitFriend>? onFriendTap;
  final ValueChanged<Orbit2Group>? onGroupTap;
  final ValueChanged<OrbitFriend>? onFriendRemove;
  final ValueChanged<Orbit2Group>? onGroupRemove;
  final void Function(OrbitFriend, Offset globalPos)? onMemberDragStart;
  final void Function(Offset globalPos)? onMemberDragUpdate;
  final void Function(Offset globalPos)? onMemberDragEnd;
  final VoidCallback? onMemberDragCancel;

  const Orbit2InnerCircle({
    super.key,
    required this.userPeerId,
    this.userAvatarBytes,
    required this.items,
    this.size = 240,
    this.expanded = false,
    this.unified = false,
    this.namesVisible = false,
    this.motionEnabled = true,
    this.carryActive = false,
    this.highlighted = false,
    this.dropLabel,
    this.carriedOutId,
    this.searchQuery = '',
    this.manageMode = false,
    this.onOverflowTap,
    this.onFriendTap,
    this.onGroupTap,
    this.onFriendRemove,
    this.onGroupRemove,
    this.onMemberDragStart,
    this.onMemberDragUpdate,
    this.onMemberDragEnd,
    this.onMemberDragCancel,
  });

  static const int _ring1Count = 5;
  static const int _ring2Count = 8;
  static const int _ring3Count = 8;

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
    final c = size / 2;
    final ring1R = size * 0.18;
    final ring2R = size * 0.31;
    final ring3R = size * 0.44;
    // In names mode the avatars SHRINK (radii fractions stay the same) so a
    // name label fits in the radial gap between rings.
    final names = namesVisible;
    final av1 = size * (names ? 0.075 : 0.12);
    final av2 = size * (names ? 0.066 : 0.10);
    final av3 = size * (names ? 0.06 : 0.09);
    final centerAv = size * (names ? 0.10 : 0.15);

    final ring1 = items.take(_ring1Count).toList();
    final ring2 = items.skip(_ring1Count).take(_ring2Count).toList();
    final ring3 = expanded
        ? items.skip(_ring1Count + _ring2Count).take(_ring3Count).toList()
        : const <Orbit2InnerItem>[];

    final shownCap = expanded ? 21 : 13;
    final overflow = items.length > shownCap ? items.length - shownCap : 0;
    final ringRadii = expanded ? [ring1R, ring2R, ring3R] : [ring1R, ring2R];

    // #1 — the "+N"/chevron control occupies the LAST slot on the outermost
    // VISIBLE ring (ring2 collapsed / ring3 expanded — both have a drawn dotted
    // orbit). Reserve a slot by adding 1 to that ring's _pos count; all members
    // stay visible and "+N" stays truthful (= items - shownCap).
    final showNode = expanded || overflow > 0;
    final outerR = expanded ? ring3R : ring2R;
    final outerRing = expanded ? 2 : 1;
    final ring2Count = ring2.length + (!expanded && showNode ? 1 : 0);
    final ring3Count = ring3.length + (expanded && showNode ? 1 : 0);
    final nodeIndex = expanded ? ring3.length : ring2.length;
    final nodeCount = expanded ? ring3Count : ring2Count;

    final q = searchQuery.trim().toLowerCase();
    final searching = q.isNotEmpty;
    final tappable = onFriendTap != null || onGroupTap != null;
    bool matches(Orbit2InnerItem it) =>
        it.displayName.toLowerCase().contains(q);

    double tap(double avatarSize) =>
        (tappable && avatarSize < 48) ? 48.0 : avatarSize;

    // Returns the avatar Positioned AND (in names mode, or as a one-off "peek"
    // for the search match) a sibling name label. By default the label is tucked
    // radially-outward in the gap toward the next ring; [labelBelow] instead
    // drops it straight under the avatar (used by One Circle's dense rings, where
    // radial labels would fan out in every direction and collide).
    List<Widget> slotFor(Orbit2InnerItem it, double sz, int globalIndex,
        int ringIndex, int ringCount, double ringR, int ring, double border,
        {bool labelBelow = false}) {
      final p = _pos(ringIndex, ringCount, ringR, ring);
      final t = tap(sz);
      final hidden = it.id == carriedOutId;
      final isMatch = searching && matches(it);
      final isDim = searching && !matches(it);

      // A group renders a distinct glyph (NOT a mini-orbit — illegible at ring
      // sizes) under a distinct key namespace so it never collides with the
      // canvas `group-node-<id>` key.
      Widget core = it.isGroup
          ? KeyedSubtree(
              key: ValueKey('inner-group-${it.id}'),
              child: _InnerGroupGlyph(size: sz, readable: readable),
            )
          : OrbitalAvatar(
              peerId: it.friend!.peerId,
              size: sz,
              globalIndex: globalIndex,
              borderWidth: border,
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
      if (manageMode) {
        avatar = Stack(
          clipBehavior: Clip.none,
          children: [
            avatar,
            const Positioned(
              top: -3,
              right: -3,
              child: IgnorePointer(child: _InnerRemoveBadge()),
            ),
          ],
        );
      }

      final out = <Widget>[
        Positioned(
          left: c + p.dx - t / 2,
          top: c + p.dy - t / 2,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // In Manage mode a tap REMOVES the member; otherwise it opens chat.
            onTap: manageMode
                ? (it.isGroup
                    ? (onGroupRemove == null
                        ? null
                        : () => onGroupRemove!(it.group!))
                    : (onFriendRemove == null
                        ? null
                        : () => onFriendRemove!(it.friend!)))
                : (it.isGroup
                    ? (onGroupTap == null ? null : () => onGroupTap!(it.group!))
                    : (onFriendTap == null
                        ? null
                        : () => onFriendTap!(it.friend!))),
            // Long-press-drag OUT to remove is friend-only (and disabled in
            // Manage mode, where a tap removes); groups are removed via Manage.
            onLongPressStart:
                (it.isGroup || manageMode || onMemberDragStart == null)
                    ? null
                    : (d) => onMemberDragStart!(it.friend!, d.globalPosition),
            onLongPressMoveUpdate:
                (it.isGroup || manageMode || onMemberDragUpdate == null)
                    ? null
                    : (d) => onMemberDragUpdate!(d.globalPosition),
            onLongPressEnd:
                (it.isGroup || manageMode || onMemberDragEnd == null)
                    ? null
                    : (d) => onMemberDragEnd!(d.globalPosition),
            // A cancelled long-press (PointerCancel: OS gesture, backgrounding,
            // ancestor claiming the pointer) skips onLongPressEnd — clear the
            // carry so the member isn't left hidden with a stuck ghost.
            onLongPressCancel:
                (it.isGroup || manageMode || onMemberDragCancel == null)
                    ? null
                    : () => onMemberDragCancel!(),
            child: SizedBox(
              width: t,
              height: t,
              child: Center(
                child: Opacity(
                  opacity: hidden ? 0.0 : (isDim ? 0.28 : 1.0),
                  child: avatar,
                ),
              ),
            ),
          ),
        ),
      ];

      if (!hidden && (names || isMatch)) {
        final lp = labelBelow
            ? Offset(p.dx, p.dy + sz / 2 + 7)
            : _pos(ringIndex, ringCount, ringR + sz / 2 + 8, ring);
        out.add(Positioned(
          // Clamp inside the cluster box so an outermost-ring label never runs
          // off the box (and the screen edge) when the ring fills up.
          left: (c + lp.dx - _kInnerLabelW / 2)
              .clamp(0.0, size - _kInnerLabelW),
          top: (c + lp.dy - 7).clamp(0.0, size - 14),
          width: _kInnerLabelW,
          child: IgnorePointer(
            child: Opacity(
              opacity: isDim ? 0.28 : 1.0,
              child: _InnerNameLabel(name: it.displayName, readable: readable),
            ),
          ),
        ));
      }
      return out;
    }

    // === "One Circle" prototype ============================================
    // Every member orbits in concentric rings sized to fit ALL of them. No
    // overflow node, no expand toggle, no scattered canvas — the circle IS the
    // whole population.
    if (unified) {
      final n = items.length;
      // Ring capacity schedule (grows outward); pick the fewest rings that hold
      // everyone, then keep adding max-capacity rings for very large crowds.
      const schedule = [6, 10, 14, 18, 22, 26];
      var ringCount = 1;
      var cumulative = 0;
      for (var k = 0; k < schedule.length; k++) {
        cumulative += schedule[k];
        ringCount = k + 1;
        if (cumulative >= n) break;
      }
      while (cumulative < n) {
        cumulative += schedule.last;
        ringCount++;
      }
      final caps = [
        for (var k = 0; k < ringCount; k++)
          k < schedule.length ? schedule[k] : schedule.last,
      ];
      final totalCap = caps.fold<int>(0, (a, b) => a + b);
      // Distribute members across rings proportional to capacity (balanced, so
      // the outermost ring isn't left sparse), then reconcile rounding to == n.
      final counts = List<int>.filled(ringCount, 0);
      if (n > 0) {
        var assigned = 0;
        for (var k = 0; k < ringCount; k++) {
          counts[k] = min(caps[k], (n * caps[k] / totalCap).round());
          assigned += counts[k];
        }
        var k = ringCount - 1;
        while (assigned < n && k >= 0) {
          if (counts[k] < caps[k]) {
            counts[k]++;
            assigned++;
          } else {
            k--;
          }
        }
        k = ringCount - 1;
        while (assigned > n && k >= 0) {
          if (counts[k] > 0) {
            counts[k]--;
            assigned--;
          } else {
            k--;
          }
        }
      }
      // Ring radii spread evenly from inner to outer. With names on, pull the
      // outer ring inward so each avatar's below-label has room before the box
      // edge (and the inner ring in, so labels don't crowd the centre "You").
      final rMin = size * 0.16;
      final rMax = size * (names ? 0.40 : 0.46);
      final radii = [
        for (var k = 0; k < ringCount; k++)
          rMin + (rMax - rMin) * (ringCount == 1 ? 0.5 : k / (ringCount - 1)),
      ];
      // One uniform avatar size: the largest the densest occupied ring fits
      // without its avatars overlapping (matches the app's single-size avatars).
      final maxAv = size * (names ? 0.085 : 0.12);
      var avUnified = maxAv;
      for (var k = 0; k < ringCount; k++) {
        if (counts[k] <= 0) continue;
        final arc = (2 * pi * radii[k]) / counts[k];
        avUnified = min(avUnified, arc * 0.72);
      }
      avUnified = avUnified.clamp(size * 0.05, maxAv);
      final centerUnified =
          min(avUnified * 1.35, rMin * 0.95).clamp(size * 0.06, size * 0.16);

      final children = <Widget>[
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _Orbit2RingPainter(radii)),
          ),
        ),
        if (userPeerId != null)
          Positioned(
            left: c - centerUnified / 2,
            top: c - centerUnified / 2,
            child: IgnorePointer(
              child: UserAvatar(
                peerId: userPeerId,
                avatarBytes: userAvatarBytes,
                size: centerUnified,
              ),
            ),
          ),
        if (userPeerId != null && names)
          Positioned(
            left: c - _kInnerLabelW / 2,
            top: c + centerUnified / 2 + 3,
            width: _kInnerLabelW,
            child: IgnorePointer(
              child: _InnerNameLabel(name: l10n.orbit2_you, readable: readable),
            ),
          ),
      ];
      var idx = 0;
      for (var k = 0; k < ringCount; k++) {
        final m = counts[k];
        for (var i = 0; i < m; i++) {
          children.addAll(
            slotFor(items[idx], avUnified, idx, i, m, radii[k], k, 1.0,
                labelBelow: true),
          );
          idx++;
        }
      }
      return SizedBox(
        width: size,
        height: size,
        child: Stack(clipBehavior: Clip.none, children: children),
      );
    }

    return AnimatedScale(
      duration: motionEnabled ? const Duration(milliseconds: 160) : Duration.zero,
      scale: highlighted ? 1.05 : 1.0,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (carryActive)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primaryAccent
                            .withValues(alpha: highlighted ? 0.95 : 0.5),
                        width: highlighted ? 2.5 : 1.5,
                      ),
                      boxShadow: highlighted
                          ? [
                              BoxShadow(
                                color: AppColors.primaryAccent
                                    .withValues(alpha: 0.4),
                                blurRadius: 30,
                                spreadRadius: 4,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _Orbit2RingPainter(ringRadii)),
              ),
            ),
            if (userPeerId != null)
              Positioned(
                left: c - centerAv / 2,
                top: c - centerAv / 2,
                child: IgnorePointer(
                  child: UserAvatar(
                    peerId: userPeerId,
                    avatarBytes: userAvatarBytes,
                    size: centerAv,
                  ),
                ),
              ),
            if (userPeerId != null && names)
              Positioned(
                left: c - _kInnerLabelW / 2,
                top: c + centerAv / 2 + 3,
                width: _kInnerLabelW,
                child: IgnorePointer(
                  child: _InnerNameLabel(name: l10n.orbit2_you, readable: readable),
                ),
              ),
            for (var i = 0; i < ring1.length; i++)
              ...slotFor(ring1[i], av1, i, i, ring1.length, ring1R, 0, 1.2),
            for (var i = 0; i < ring2.length; i++)
              ...slotFor(ring2[i], av2, _ring1Count + i, i, ring2Count, ring2R,
                  1, 1),
            for (var i = 0; i < ring3.length; i++)
              ...slotFor(ring3[i], av3, _ring1Count + _ring2Count + i, i,
                  ring3Count, ring3R, 2, 1),
            if (showNode)
              Builder(builder: (_) {
                final np = _pos(nodeIndex, nodeCount, outerR, outerRing);
                return Positioned(
                  left: c + np.dx - 15,
                  top: c + np.dy - 15,
                  child: GestureDetector(
                    key: const ValueKey('inner-expand-toggle'),
                    onTap: onOverflowTap,
                    behavior: HitTestBehavior.opaque,
                    child: _OrbitExpandNode(
                      expanded: expanded,
                      count: overflow,
                      readable: readable,
                      semanticLabel:
                          expanded ? l10n.orbit2_show_less : '+$overflow',
                    ),
                  ),
                );
              }),
            if (carryActive)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: _DropChip(
                      label: dropLabel != null
                          ? l10n.orbit2_release_to_add(dropLabel!)
                          : l10n.orbit2_drop_hint,
                      active: highlighted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A small circular orbital "more" node — a frosted node on the orbit edge,
/// showing "+N" (collapsed) or a chevron (expanded). Not a banner.
class _OrbitExpandNode extends StatelessWidget {
  final bool expanded;
  final int count;
  final BackgroundReadableColors readable;
  final String semanticLabel;

  const _OrbitExpandNode({
    required this.expanded,
    required this.count,
    required this.readable,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      // A flat translucent disc (no BackdropFilter): the node always renders
      // over the fixed dark starfield, so a solid glass fill is visually
      // indistinguishable from a blur but avoids a per-frame backdrop re-sample
      // every time the inner cluster is dragged.
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
                  '+$count',
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

/// Decorative remove affordance on an inner-circle member in Manage mode.
/// Purely visual ([IgnorePointer] at the call site) — the member's tap removes.
class _InnerRemoveBadge extends StatelessWidget {
  const _InnerRemoveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 15,
      height: 15,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFE5484D),
        border: Border.all(color: Colors.white, width: 1.3),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
      ),
      child: const Icon(Icons.remove_rounded, size: 10, color: Colors.white),
    );
  }
}

/// A tiny, no-pill name label for an inner-circle member, sitting in the radial
/// gap toward the next ring. A faint shadow keeps it legible over the orbits.
class _InnerNameLabel extends StatelessWidget {
  final String name;
  final BackgroundReadableColors readable;
  const _InnerNameLabel({required this.name, required this.readable});

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

/// A compact, legible inner-circle group node: a teal disc with a group glyph
/// (deliberately NOT a mini Orbit2GroupNode, which is an illegible smudge at
/// inner-ring sizes).
class _InnerGroupGlyph extends StatelessWidget {
  final double size;
  final BackgroundReadableColors readable;
  const _InnerGroupGlyph({required this.size, required this.readable});

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

class _Orbit2RingPainter extends CustomPainter {
  final List<double> radii;
  const _Orbit2RingPainter(this.radii);

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
  bool shouldRepaint(covariant _Orbit2RingPainter old) =>
      !listEquals(old.radii, radii);
}

class _DropChip extends StatelessWidget {
  final String label;
  final bool active;
  const _DropChip({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: active
            ? AppColors.primaryAccent.withValues(alpha: 0.92)
            : Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primaryAccent.withValues(alpha: active ? 1 : 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.add_circle_rounded : Icons.add_rounded,
            size: 15,
            color: Colors.white,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
