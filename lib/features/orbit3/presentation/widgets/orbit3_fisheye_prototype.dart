import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_group.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_inner_item.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../domain/orbit3_one_circle_layout.dart';

/// Prototype B — "Fisheye / Orbit-Climb".
///
/// The OTHER direction the user wanted to feel: ONE radial orbit holds EVERYONE
/// (~50), but only the focused tier is drawn full-size and legible — tiers away
/// from focus compress into faint dot-rings (a degree-of-interest fisheye). Drag
/// vertically to "climb" outward through your network; tap a faint member to
/// bring its tier into focus; tap a focused member to open the chat; long-press a
/// focused member to pull them into your innermost tier (re-tier). Visuals-only.
class Orbit3FisheyePrototype extends StatefulWidget {
  final String? userPeerId;
  final Uint8List? userAvatarBytes;
  final List<Orbit2InnerItem> items;
  final bool namesVisible;
  final bool motionEnabled;
  final VoidCallback? onToggleNames;
  final ValueChanged<OrbitFriend>? onFriendTap;
  final ValueChanged<Orbit2Group>? onGroupTap;

  const Orbit3FisheyePrototype({
    super.key,
    required this.userPeerId,
    this.userAvatarBytes,
    required this.items,
    this.namesVisible = true,
    this.motionEnabled = true,
    this.onToggleNames,
    this.onFriendTap,
    this.onGroupTap,
  });

  @override
  State<Orbit3FisheyePrototype> createState() => _Orbit3FisheyePrototypeState();
}

class _Orbit3FisheyePrototypeState extends State<Orbit3FisheyePrototype> {
  // The member order — sequential fill into rings reads from this, so moving an
  // id to the front "promotes" them toward the inner tier.
  late List<String> _order;

  // Which tier is in focus (fractional while dragging — smooth fisheye).
  double _focus = 0;

  // Radial fisheye lens constants.
  static const double _focusRadius = 132; // where the in-focus tier sits
  static const double _amplitude = 122; // how far in/out neighbours splay
  static const double _spread = 1.25; // tier separation near focus
  static const double _pxPerTier = 92; // drag sensitivity

  @override
  void initState() {
    super.initState();
    _order = widget.items.map((it) => it.id).toList();
  }

  @override
  void didUpdateWidget(covariant Orbit3FisheyePrototype old) {
    super.didUpdateWidget(old);
    // Keep the order in sync if the population changed (e.g. the count cycler).
    final ids = widget.items.map((it) => it.id).toSet();
    if (ids.length != _order.length || !_order.every(ids.contains)) {
      _order = widget.items.map((it) => it.id).toList();
      _focus = _focus.clamp(0, max(0, _ringCount - 1)).toDouble();
    }
  }

  Map<String, Orbit2InnerItem> get _byId => {
    for (final it in widget.items) it.id: it,
  };

  List<Orbit2InnerItem> get _ordered {
    final byId = _byId;
    return [
      for (final id in _order)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// Members grouped into Orbit-parity capacity rings (5, 8, 11, 14, …).
  List<List<Orbit2InnerItem>> get _rings {
    final ordered = _ordered;
    final rings = <List<Orbit2InnerItem>>[];
    var i = 0;
    var k = 0;
    while (i < ordered.length) {
      final cap = orbit3RingCapacity(k);
      final end = min(i + cap, ordered.length);
      rings.add(ordered.sublist(i, end));
      i = end;
      k++;
    }
    return rings;
  }

  int get _ringCount => _rings.length;

  static double _tanh(double x) {
    final e2 = exp(2 * x);
    return (e2 - 1) / (e2 + 1);
  }

  double _screenRadius(double dist) =>
      _focusRadius + _amplitude * _tanh(dist / _spread);

  double _weight(double dist) => 1 / (1 + (dist / 0.85) * (dist / 0.85));

  void _onDrag(DragUpdateDetails d) {
    // Drag UP (negative dy) climbs OUTWARD (focus increases).
    setState(() {
      _focus = (_focus - d.delta.dy / _pxPerTier)
          .clamp(0, max(0, _ringCount - 1))
          .toDouble();
    });
  }

  void _onDragEnd(DragEndDetails d) {
    HapticFeedback.selectionClick();
    setState(() => _focus = _focus.roundToDouble());
  }

  void _focusTier(int k) {
    HapticFeedback.selectionClick();
    setState(() => _focus = k.toDouble().clamp(0, max(0, _ringCount - 1)));
  }

  void _onMemberTap(Orbit2InnerItem it, int ringK) {
    final focused = (ringK - _focus).abs() < 0.5;
    if (!focused) {
      _focusTier(ringK); // first tap brings the tier into focus
      return;
    }
    if (it.isGroup) {
      widget.onGroupTap?.call(it.group!);
    } else {
      widget.onFriendTap?.call(it.friend!);
    }
  }

  void _promoteToInner(Orbit2InnerItem it) {
    final l10n = AppLocalizations.of(context)!;
    HapticFeedback.mediumImpact();
    final prev = List<String>.from(_order);
    setState(() {
      _order.remove(it.id);
      _order.insert(0, it.id);
      _focus = 0;
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text(l10n.orbit3_pulled_into_inner_tier(it.displayName)),
          action: SnackBarAction(
            label: l10n.feed_undo,
            onPressed: () => setState(() => _order = prev),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final readable = context.backgroundReadableColors;
    final rings = _rings;
    final ringCount = rings.length;
    final focusInt = _focus.round().clamp(0, max(0, ringCount - 1)).toInt();
    final focusedCount = ringCount == 0 ? 0 : rings[focusInt].length;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onDrag,
      onVerticalDragEnd: _onDragEnd,
      onDoubleTap: widget.onToggleNames,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 360.0;
          final h = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 560.0;
          final center = Offset(w / 2, h / 2);

          final children = <Widget>[
            // Faint guide rings for the visible tiers.
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _FisheyeRingPainter(
                    center: center,
                    radii: [
                      for (var k = 0; k < ringCount; k++)
                        _screenRadius(k - _focus),
                    ],
                    weights: [
                      for (var k = 0; k < ringCount; k++) _weight(k - _focus),
                    ],
                  ),
                ),
              ),
            ),
          ];

          // Draw rings far→near so focused avatars paint on top.
          final drawOrder = [
            for (var k = 0; k < ringCount; k++) k,
          ]..sort((a, b) => _weight(b - _focus).compareTo(_weight(a - _focus)));
          for (final k in drawOrder) {
            final dist = k - _focus;
            final radius = _screenRadius(dist);
            final wgt = _weight(dist);
            final size = 9 + (38 - 9) * wgt;
            final opacity = (0.2 + 0.8 * wgt).clamp(0.0, 1.0);
            final showName = (widget.namesVisible || wgt > 0.55) && wgt > 0.55;
            final members = rings[k];
            final count = members.length;
            for (var i = 0; i < count; i++) {
              final stagger = k * 14;
              final angle = (i * 360 / count + stagger - 90) * (pi / 180);
              final p = Offset(
                center.dx + cos(angle) * radius,
                center.dy + sin(angle) * radius,
              );
              children.addAll(
                _member(
                  members[i],
                  ringK: k,
                  globalIndex: _order.indexOf(members[i].id),
                  pos: p,
                  size: size,
                  opacity: opacity,
                  showName: showName,
                  box: Size(w, h),
                  readable: readable,
                ),
              );
            }
          }

          // Center "You".
          if (widget.userPeerId != null) {
            children.add(
              Positioned(
                left: center.dx - 26,
                top: center.dy - 26,
                child: IgnorePointer(
                  child: UserAvatar(
                    peerId: widget.userPeerId,
                    avatarBytes: widget.userAvatarBytes,
                    size: 52,
                  ),
                ),
              ),
            );
          }

          // Tier rail (right edge) + focused-tier label (top).
          children.add(
            Positioned(
              right: 6,
              top: 0,
              bottom: 0,
              child: _TierRail(
                count: ringCount,
                focus: _focus,
                readable: readable,
                onTap: _focusTier,
              ),
            ),
          );
          children.add(
            Positioned(
              left: 0,
              right: 0,
              top: 6,
              child: Center(
                child: _GlassChip(
                  readable: readable,
                  text: ringCount == 0
                      ? 'No one yet'
                      : 'Tier ${focusInt + 1} · $focusedCount people · drag ↕ to travel',
                ),
              ),
            ),
          );

          return Stack(clipBehavior: Clip.none, children: children);
        },
      ),
    );
  }

  List<Widget> _member(
    Orbit2InnerItem it, {
    required int ringK,
    required int globalIndex,
    required Offset pos,
    required double size,
    required double opacity,
    required bool showName,
    required Size box,
    required BackgroundReadableColors readable,
  }) {
    final tap = max(size, 36.0);
    final Widget core = size < 16
        ? _Dot(size: size, isGroup: it.isGroup, readable: readable)
        : (it.isGroup
              ? Container(
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
                  child: Icon(
                    Icons.group_rounded,
                    size: size * 0.5,
                    color: Colors.black87,
                  ),
                )
              : OrbitalAvatar(
                  peerId: it.friend!.peerId,
                  size: size,
                  globalIndex: globalIndex,
                  motionEnabled: widget.motionEnabled,
                  borderWidth: 1,
                  borderColor: readable.border.withValues(alpha: 0.18),
                  semanticLabel: 'Open chat with ${it.displayName}',
                ));

    final out = <Widget>[
      Positioned(
        left: pos.dx - tap / 2,
        top: pos.dy - tap / 2,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onMemberTap(it, ringK),
          onLongPress: () => _promoteToInner(it),
          child: SizedBox(
            width: tap,
            height: tap,
            child: Center(
              child: Opacity(opacity: opacity, child: core),
            ),
          ),
        ),
      ),
    ];

    if (showName) {
      const lw = 60.0;
      out.add(
        Positioned(
          left: (pos.dx - lw / 2).clamp(0.0, box.width - lw),
          top: (pos.dy + size / 2 + 5).clamp(0.0, box.height - 14),
          width: lw,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity,
              child: Text(
                it.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: readable.textPrimary,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 3)],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return out;
  }
}

class _Dot extends StatelessWidget {
  final double size;
  final bool isGroup;
  final BackgroundReadableColors readable;
  const _Dot({
    required this.size,
    required this.isGroup,
    required this.readable,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.clamp(5.0, 14.0),
      height: size.clamp(5.0, 14.0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (isGroup ? AppColors.tealAccent : AppColors.primaryAccent)
            .withValues(alpha: 0.7),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryAccent.withValues(alpha: 0.25),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }
}

/// The vertical tier selector on the right rim.
class _TierRail extends StatelessWidget {
  final int count;
  final double focus;
  final BackgroundReadableColors readable;
  final ValueChanged<int> onTap;

  const _TierRail({
    required this.count,
    required this.focus,
    required this.readable,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var k = 0; k < count; k++)
          GestureDetector(
            onTap: () => onTap(k),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: (k - focus).abs() < 0.5 ? 18 : 8,
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: (k - focus).abs() < 0.5
                      ? AppColors.primaryAccent
                      : readable.iconMuted.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _GlassChip extends StatelessWidget {
  final BackgroundReadableColors readable;
  final String text;
  const _GlassChip({required this.readable, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: readable.glassSurface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: readable.glassBorder),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: readable.textSecondary,
        ),
      ),
    );
  }
}

class _FisheyeRingPainter extends CustomPainter {
  final Offset center;
  final List<double> radii;
  final List<double> weights;
  const _FisheyeRingPainter({
    required this.center,
    required this.radii,
    required this.weights,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var k = 0; k < radii.length; k++) {
      final r = radii[k];
      if (r <= 2) continue;
      final w = weights[k];
      final paint = Paint()
        ..color = const Color(
          0xFF81E6D9,
        ).withValues(alpha: (0.08 + 0.32 * w).clamp(0.0, 0.4))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 + 1.2 * w;
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FisheyeRingPainter old) =>
      old.center != center ||
      old.radii.length != radii.length ||
      old.weights.length != weights.length ||
      _firstDiff(old.radii, radii) ||
      _firstDiff(old.weights, weights);

  static bool _firstDiff(List<double> a, List<double> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if ((a[i] - b[i]).abs() > 0.01) return true;
    }
    return false;
  }
}
