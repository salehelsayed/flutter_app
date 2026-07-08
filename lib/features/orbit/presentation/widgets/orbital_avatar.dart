import 'package:flutter/material.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/unread_orbit_indicator.dart';

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
    final avatar = SizedBox(
      width: tapTargetSize,
      height: tapTargetSize,
      // Stack is Clip.none so the unread indicator (ring at ~1.35x avatar
      // radius) may overpaint the 48-box — the host visualization Stack is
      // Clip.none too. The indicator is a sibling (not a wrapper) so satellite
      // rotation cannot rebuild the avatar/child subtree (TC-194-36).
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Center(
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.borderColor,
                  width: widget.borderWidth,
                ),
              ),
              child: ClipOval(
                child: widget.child ??
                    UserAvatar(
                      peerId: widget.peerId,
                      size: widget.size - widget.borderWidth * 2,
                    ),
              ),
            ),
          ),
          if (widget.unreadCount > 0)
            // Non-hit-testing + semantics-neutral: the unread state is conveyed
            // through the node's own semantic label (built by the visualization),
            // and the 48px opaque GestureDetector stays the sole tap target.
            ExcludeSemantics(
              child: IgnorePointer(
                // The indicator sizes ITSELF to ~1.66x the avatar (ring at 1.35x
                // radius + satellite halo) and lays its satellites out around
                // that self-assumed box center. This tap-target Stack is only
                // ~48px, which CLAMPS the indicator below its natural size so
                // its internal center drifts from the real box center and the
                // satellites shear off-axis. Clip.none stops the clip, not the
                // constraint — so hand it unbounded constraints via OverflowBox
                // and let it overpaint the box, centered on the node.
                child: OverflowBox(
                  minWidth: 0,
                  maxWidth: double.infinity,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: UnreadOrbitIndicator(
                    unreadCount: widget.unreadCount,
                    diameter: widget.size,
                    motionEnabled: widget.unreadMotionEnabled,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    final child = widget.onTap == null
        ? avatar
        : Semantics(
            label: widget.semanticLabel,
            button: true,
            child: GestureDetector(
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
