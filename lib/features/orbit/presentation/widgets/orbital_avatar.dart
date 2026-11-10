import 'package:flutter/material.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/unread_orbit_indicator.dart';

enum OrbitalAvatarFocusTreatment { none, halo }

/// A positioned avatar on an orbital ring with a staggered entrance animation.
///
/// Uses [SingleTickerProviderStateMixin] for its entrance animation.
///
/// The base behavior (in-place scale + fade, 500ms, staggered by
/// `globalIndex*40ms`) is the default for every consumer (Orbit/Orbit2/Orbit3/
/// feed). The 168 additive params ([child], [riseUp], [entranceDelayMs],
/// [animateEntrance]) are all defaulted to reproduce that default exactly, so
/// they only change behavior where explicitly opted into (the Orbit3 arch).
class OrbitalAvatar extends StatefulWidget {
  final String peerId;
  final double size;
  final int globalIndex;
  final double borderWidth;
  final Color borderColor;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool motionEnabled;

  /// Render this instead of the peer photo (e.g. a group glyph) inside the same
  /// bordered circle + entrance — so groups read the same as 1:1 avatars (168 C2).
  final Widget? child;

  /// Opt-in "rise up + scale-in + fade" fast entrance (avatars rushing up toward
  /// the user "like commits from a far distance") instead of the in-place
  /// scale+fade. Used by the Orbit3 arch expansion (168 C3).
  final bool riseUp;

  /// Override the entrance start delay (default `globalIndex*40ms`). Used to
  /// order the arch entrance bottom→up (168 C3).
  final int? entranceDelayMs;

  /// When false, appear fully with NO entrance (independent of [motionEnabled]) —
  /// keeps the Orbit3 inner circle steady when the arch expands (168 C4).
  final bool animateEntrance;

  /// 194 — unread messages on this friend. `> 0` overlays the messenger-orbit
  /// [UnreadOrbitIndicator] on the node; `0` renders nothing (no ticker).
  final int unreadCount;

  /// 194 — when false the unread indicator's rotation is frozen (still visible).
  /// Threaded from the visualization's reduce-motion read.
  final bool unreadMotionEnabled;
  final bool focused;
  final bool quietEntrance;
  final Color? unreadAccent;
  final OrbitalAvatarFocusTreatment focusTreatment;
  final bool avatarGlowEnabled;
  final bool unreadCountBadge;

  /// Non-null when this friend has an unopened thought and the thought titles
  /// are hidden: a star orbits the node in this colour (light backgrounds).
  final Color? thoughtStarColor;

  const OrbitalAvatar({
    super.key,
    required this.peerId,
    required this.size,
    required this.globalIndex,
    this.borderWidth = 1.5,
    this.borderColor = const Color(0x1FFFFFFF),
    this.onTap,
    this.semanticLabel,
    this.motionEnabled = true,
    this.child,
    this.riseUp = false,
    this.entranceDelayMs,
    this.animateEntrance = true,
    this.unreadCount = 0,
    this.unreadMotionEnabled = true,
    this.focused = false,
    this.quietEntrance = false,
    this.unreadAccent,
    this.focusTreatment = OrbitalAvatarFocusTreatment.none,
    this.avatarGlowEnabled = false,
    this.unreadCountBadge = false,
    this.thoughtStarColor,
  });

  @override
  State<OrbitalAvatar> createState() => _OrbitalAvatarState();
}

class _OrbitalAvatarState extends State<OrbitalAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      // Fast for the rise-up entrance; the classic scale+fade keeps 500ms.
      duration: Duration(milliseconds: widget.riseUp ? 220 : 500),
    );
    _scaleAnimation = CurvedAnimation(parent: _controller, curve: Curves.ease);

    if (widget.motionEnabled && widget.animateEntrance) {
      final delay = widget.entranceDelayMs ?? widget.globalIndex * 40;
      Future.delayed(Duration(milliseconds: delay), () {
        if (mounted) _controller.forward();
      });
    } else {
      // Reduce Motion OR suppressed entrance: appear fully, no animation.
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tapTargetSize = widget.onTap == null || widget.size >= 48
        ? widget.size
        : 48.0;
    final accent = widget.unreadAccent ?? UnreadOrbitIndicator.kUnreadAccent;
    final face = Center(
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: widget.borderColor,
            width: widget.borderWidth,
          ),
          boxShadow: widget.avatarGlowEnabled
              ? [
                  BoxShadow(
                    color: widget.borderColor.withValues(alpha: 0.22),
                    blurRadius: 9,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: ClipOval(
          child:
              widget.child ??
              UserAvatar(
                peerId: widget.peerId,
                size: widget.size - widget.borderWidth * 2,
              ),
        ),
      ),
    );
    final avatar = SizedBox(
      width: tapTargetSize,
      height: tapTargetSize,
      // Stack is Clip.none so the orbit may overpaint the 48-box — the host
      // visualization Stack is Clip.none too.
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (widget.focusTreatment == OrbitalAvatarFocusTreatment.halo)
            Container(
              key: const ValueKey('orbit-node-focus-cue'),
              width: widget.size + 12,
              height: widget.size + 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.borderColor.withValues(alpha: 0.72),
                  width: 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.borderColor.withValues(alpha: 0.18),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          if (widget.unreadCount > 0 || widget.thoughtStarColor != null)
            // The orbit wraps the face so its back half paints under it and its
            // front half over it. It adds no semantics and never hit-tests, so
            // the node's own label and the 48px GestureDetector stay as they
            // were; the face is passed through untouched (TC-194-36).
            UnreadOrbitIndicator(
              unreadCount: widget.unreadCount,
              diameter: widget.size,
              motionEnabled: widget.unreadMotionEnabled,
              accent: accent,
              showSatellites: !widget.unreadCountBadge,
              showCountBadge: widget.unreadCountBadge,
              thoughtStarColor: widget.thoughtStarColor,
              child: face,
            )
          else
            face,
        ],
      ),
    );
    final child = widget.onTap == null
        ? avatar
        : Semantics(
            label: widget.semanticLabel,
            button: true,
            child: GestureDetector(
              // Keep the slot's entrance animation, but retire an in-flight
              // gesture when a refresh replaces the entity occupying it.
              key: ValueKey(widget.peerId),
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: avatar,
            ),
          );

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        final v = _scaleAnimation.value;
        final scaled = Transform.scale(
          // Rise-up scales from "far" (small) to "near"; classic is 0→1.
          scale: widget.riseUp ? (0.4 + 0.6 * v) : v,
          child: Opacity(opacity: v, child: child),
        );
        if (!widget.riseUp) return scaled;
        // Slide up from below toward the user as it appears.
        final rise = widget.size * 0.9 * (1 - v);
        return Transform.translate(offset: Offset(0, rise), child: scaled);
      },
      child: child,
    );
  }
}
