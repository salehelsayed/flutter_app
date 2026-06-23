import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_group.dart';
import 'package:flutter_app/features/orbit3/domain/orbit3_connection_profile.dart';
import 'package:flutter_app/features/orbit3/domain/orbit3_constellation_geometry.dart';

import 'orbit3_constellation_painters.dart';

/// Width budget for a star's name label.
const double _kLabelW = 64;

/// How many of the brightest stars carry an always-on label when names are on.
const int _kMaxLabels = 10;

/// Below this zoom members are pure stars; above [_kAvatarFullZoom] their avatar
/// photo has fully bloomed in. Between, it cross-fades — so zooming in feels like
/// flying close enough to a star to see who it is.
const double _kAvatarStartZoom = 1.5;
const double _kAvatarFullZoom = 2.25;

/// Orbit3's deterministic "relationship constellation" — a night-sky fingerprint
/// of your orbit, arranged by how you got to know each other.
///
/// Members render as STARS (sized by how much you chat, coloured by who talks
/// more), connected into a figure by the per-mode lines. Tap a star to SELECT it
/// — it blooms into that person's avatar with their name. Pinch to zoom in and
/// the whole sky blooms into faces through a deepening milky way.
class Orbit3Constellation extends StatefulWidget {
  final String? userPeerId;
  final Uint8List? userAvatarBytes;
  final List<Orbit3ConnectionProfile> profiles;
  final Orbit3ConstellationMode mode;
  final bool namesVisible;
  final bool motionEnabled;
  final String searchQuery;

  /// 0..1 animation phase for the star twinkle (held at 0 under reduce-motion).
  final double t;

  /// Current pinch-zoom scale (1 = fit). Reveals the milky way + blooms avatars.
  final double zoom;

  final VoidCallback? onToggleNames;
  final ValueChanged<OrbitFriend>? onFriendTap;
  final ValueChanged<Orbit2Group>? onGroupTap;

  const Orbit3Constellation({
    super.key,
    required this.userPeerId,
    this.userAvatarBytes,
    required this.profiles,
    this.mode = Orbit3ConstellationMode.zodiac,
    this.namesVisible = true,
    this.motionEnabled = true,
    this.searchQuery = '',
    this.t = 0.0,
    this.zoom = 1.0,
    this.onToggleNames,
    this.onFriendTap,
    this.onGroupTap,
  });

  @override
  State<Orbit3Constellation> createState() => _Orbit3ConstellationState();
}

class _Orbit3ConstellationState extends State<Orbit3Constellation> {
  /// The currently selected star (tapped once) — shows its name + avatar.
  String? _selected;

  void _onTapStar(Orbit3Placement pl) {
    if (_selected != pl.id) {
      HapticFeedback.selectionClick();
      setState(() => _selected = pl.id);
    } else {
      _open(pl); // a second tap on the selected star opens the chat
    }
  }

  void _open(Orbit3Placement pl) {
    final p = pl.driver.profile;
    if (p.isGroup) {
      widget.onGroupTap?.call(p.item.group!);
    } else {
      widget.onFriendTap?.call(p.item.friend!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final readable = context.backgroundReadableColors;
    const box = kOrbit3ConstellationBox;
    final c = box / 2;

    final set = Orbit3DriverSet.from(widget.profiles);
    final geo = computeOrbit3Constellation(
        set: set, mode: widget.mode, box: box, userSeed: widget.userPeerId);

    // Keep the selection valid across archetype/mode changes.
    final selected = geo.byId.containsKey(_selected) ? _selected : null;

    final byMag = [...geo.placements]
      ..sort((a, b) => b.driver.magnitude.compareTo(a.driver.magnitude));
    final labelled = byMag.take(_kMaxLabels).map((p) => p.id).toSet();

    final q = widget.searchQuery.trim().toLowerCase();
    final searching = q.isNotEmpty;
    bool matches(Orbit3Placement p) =>
        p.driver.profile.displayName.toLowerCase().contains(q);

    // How far avatars have bloomed out of their stars (0 = pure star sky).
    final zoomReveal = ((widget.zoom - _kAvatarStartZoom) /
            (_kAvatarFullZoom - _kAvatarStartZoom))
        .clamp(0.0, 1.0);

    final painter = switch (widget.mode) {
      Orbit3ConstellationMode.zodiac => Orbit3ZodiacPainter(
          geo: geo,
          t: widget.t,
          motion: widget.motionEnabled,
          lineColor: readable.textPrimary,
          coronaColor: AppColors.secondaryAccent,
          zoom: widget.zoom),
      Orbit3ConstellationMode.galaxy => Orbit3GalaxyArmPainter(
          geo: geo,
          t: widget.t,
          motion: widget.motionEnabled,
          lineColor: readable.textPrimary,
          coronaColor: AppColors.secondaryAccent,
          zoom: widget.zoom),
      Orbit3ConstellationMode.gravity => Orbit3GravityFieldPainter(
          geo: geo,
          t: widget.t,
          motion: widget.motionEnabled,
          lineColor: readable.textPrimary,
          coronaColor: AppColors.secondaryAccent,
          zoom: widget.zoom),
    };

    final children = <Widget>[
      Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: painter))),
    ];

    for (var i = 0; i < geo.placements.length; i++) {
      final pl = geo.placements[i];
      final p = pl.driver.profile;
      final isMatch = searching && matches(pl);
      final isDim = searching && !isMatch;
      final isSelected = selected == pl.id;
      final highlighted = isMatch || isSelected;
      // Avatar blooms in on zoom, or instantly when selected / search-matched.
      final reveal = highlighted ? 1.0 : zoomReveal;
      final avDiam = pl.avDiam;
      final tapT = avDiam < 48 ? 48.0 : avDiam;

      if (reveal > 0.01) {
        Widget core = p.isGroup
            ? _GroupGlyph(size: avDiam, readable: readable)
            : OrbitalAvatar(
                peerId: p.item.friend!.peerId,
                size: avDiam,
                globalIndex: i,
                borderWidth: 1.6,
                borderColor: pl.hue.withValues(alpha: 0.9),
                semanticLabel: 'Open chat with ${p.displayName}',
                motionEnabled: widget.motionEnabled,
              );
        if (highlighted) {
          core = DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (isSelected ? AppColors.secondaryAccent : pl.hue)
                      .withValues(alpha: 0.7),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: core,
          );
        }
        children.add(Positioned(
          left: c + pl.pos.dx - tapT / 2,
          top: c + pl.pos.dy - tapT / 2,
          child: IgnorePointer(
            child: SizedBox(
              width: tapT,
              height: tapT,
              child: Center(
                child: Opacity(
                  opacity: (reveal * (isDim ? 0.28 : pl.opacity)).clamp(0.0, 1.0),
                  child: core,
                ),
              ),
            ),
          ),
        ));
      }

      // The tap target is ALWAYS present (even for a pure, un-bloomed star) so a
      // star can be selected from the night sky.
      children.add(Positioned(
        left: c + pl.pos.dx - tapT / 2,
        top: c + pl.pos.dy - tapT / 2,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onTapStar(pl),
          child: SizedBox(width: tapT, height: tapT),
        ),
      ));

      final wantLabel = (!isSelected) &&
          (isMatch ||
              (widget.namesVisible && labelled.contains(pl.id)) ||
              widget.zoom > 1.9);
      if (wantLabel) {
        children.add(Positioned(
          left: (c + pl.pos.dx - _kLabelW / 2).clamp(0.0, box - _kLabelW),
          top: (c + pl.pos.dy + avDiam / 2 + 6).clamp(0.0, box - 14),
          width: _kLabelW,
          child: IgnorePointer(
            child: Opacity(
              opacity: isDim ? 0.28 : 1.0,
              child: _ConstNameLabel(name: p.displayName, readable: readable),
            ),
          ),
        ));
      }
    }

    // The "You" sun, on top at the center.
    children.add(Positioned(
      left: c - 27,
      top: c - 27,
      child: IgnorePointer(
        child: widget.userPeerId != null
            ? UserAvatar(
                peerId: widget.userPeerId,
                avatarBytes: widget.userAvatarBytes,
                size: 54,
              )
            : Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(colors: [
                    AppColors.secondaryAccent,
                    AppColors.primaryAccent,
                  ]),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryAccent.withValues(alpha: 0.5),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
      ),
    ));
    if (widget.namesVisible) {
      children.add(Positioned(
        left: c - _kLabelW / 2,
        top: c + 27 + 4,
        width: _kLabelW,
        child: IgnorePointer(
          child: _ConstNameLabel(name: 'You', readable: readable),
        ),
      ));
    }

    // The selected star's name card, on top of everything (tap it to open chat).
    if (selected != null) {
      final pl = geo.byId[selected]!;
      children.add(Positioned(
        left: (c + pl.pos.dx - 66).clamp(0.0, box - 132),
        top: (c + pl.pos.dy + pl.avDiam / 2 + 8).clamp(0.0, box - 34),
        width: 132,
        child: Center(
          child: _SelectedNameCard(
            name: pl.driver.profile.displayName,
            readable: readable,
            onOpen: () => _open(pl),
          ),
        ),
      ));
    }

    // Double-tap anywhere toggles names; a single tap on empty sky deselects.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: selected == null ? null : () => setState(() => _selected = null),
      onDoubleTap: widget.onToggleNames == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onToggleNames!();
            },
      child: SizedBox(
        width: box,
        height: box,
        child: Stack(clipBehavior: Clip.none, children: children),
      ),
    );
  }
}

/// A compact group node (teal disc + glyph). Constellation archetypes are
/// friends-only today, but this keeps the widget total if a group is ever added.
class _GroupGlyph extends StatelessWidget {
  final double size;
  final BackgroundReadableColors readable;
  const _GroupGlyph({required this.size, required this.readable});

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

/// A tiny shadowed name label sitting just under a star.
class _ConstNameLabel extends StatelessWidget {
  final String name;
  final BackgroundReadableColors readable;
  const _ConstNameLabel({required this.name, required this.readable});

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

/// The little glassy card shown under a selected star: the person's name + an
/// "open" hint. Tapping it opens their chat.
class _SelectedNameCard extends StatelessWidget {
  final String name;
  final BackgroundReadableColors readable;
  final VoidCallback onOpen;
  const _SelectedNameCard({
    required this.name,
    required this.readable,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: readable.glassSurface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
              color: AppColors.secondaryAccent.withValues(alpha: 0.55)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: readable.textPrimary,
              ),
            ),
            Text(
              'tap to open',
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w600,
                color: readable.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
