import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit2/domain/models/avatar_tier.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_friend.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_group.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_inner_item.dart';
import 'package:flutter_app/features/orbit2/presentation/screens/orbit2_mock_chat_screen.dart';
import 'package:flutter_app/features/orbit2/presentation/widgets/orbit2_backdrop.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../application/orbit3_archetype_data.dart';
import '../../application/orbit3_mock_data.dart';
import '../../domain/orbit3_connection_profile.dart';
import '../../domain/orbit3_constellation_geometry.dart';
import '../widgets/orbit3_constellation.dart';
import '../widgets/orbit3_one_circle.dart';

/// Which Orbit3 view is on screen: the packed One Circle, or the new
/// deterministic relationship constellation ("horoscope") fingerprint.
enum Orbit3ViewMode { oneCircle, constellation }

/// Orbit3 — a minimal, self-contained "One Circle" prototype (visuals only).
///
/// Reproduces ONLY Orbit2's unified one-circle view as a 4th nav tab, plus two
/// capabilities the user asked for: a reliable double-tap-anywhere names toggle
/// and graceful packing/rendering up to ~50 members in one readable circle.
class Orbit3Screen extends StatefulWidget {
  final String? userPeerId;
  final Uint8List? userAvatarBytes;
  final BackgroundPreference backgroundPreference;
  final String? activeTab;
  final void Function(String)? onSwitchView;

  const Orbit3Screen({
    super.key,
    this.userPeerId,
    this.userAvatarBytes,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
    this.activeTab,
    this.onSwitchView,
  });

  @override
  State<Orbit3Screen> createState() => _Orbit3ScreenState();
}

class _Orbit3ScreenState extends State<Orbit3Screen>
    with TickerProviderStateMixin {
  // Population milestones: 1 full ring (5), 2 full rings (13), expand-needed (24),
  // many rings (50).
  static const List<int> _populations = [5, 13, 24, 50];

  int _populationIndex = 2;
  final List<Orbit2InnerItem> _items = [];
  bool _namesVisible = true;
  bool _expanded = false;
  String _searchQuery = '';

  // Constellation ("horoscope") sub-view state.
  Orbit3ViewMode _viewMode = Orbit3ViewMode.oneCircle;
  Orbit3ConstellationMode _constMode = Orbit3ConstellationMode.zodiac;
  Orbit3Archetype _archetype = Orbit3Archetype.connector;
  List<Orbit3ConnectionProfile> _profiles = const [];

  // Drives the star twinkle / glow breathing (one shared controller).
  late final AnimationController _twinkle;

  // Pinch-zoom + pan for exploring the constellation (the "fly into the galaxy"
  // gesture). Reset whenever the picture changes so you never start zoomed in.
  final TransformationController _constZoom = TransformationController();

  // Drives the on-screen ＋/－ zoom buttons (pinch is fiddly on a simulator).
  late final AnimationController _zoomAnim;
  Animation<Matrix4>? _zoomTween;
  Size _viewport = const Size(360, 360);

  @override
  void initState() {
    super.initState();
    _rebuildMock();
    _rebuildArchetype();
    _twinkle = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _zoomAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..addListener(() {
        final tw = _zoomTween;
        if (tw != null) _constZoom.value = tw.value;
      });
  }

  @override
  void dispose() {
    _twinkle.dispose();
    _zoomAnim.dispose();
    _constZoom.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _zoomAnim.stop();
    _zoomTween = null;
    _constZoom.value = Matrix4.identity();
  }

  // Smoothly animate to [scale], zooming about the centre of the view.
  void _animateZoomTo(double scale) {
    final center = Offset(_viewport.width / 2, _viewport.height / 2);
    // Scale about [center]: x' = s·x + cx·(1−s) — built directly to avoid the
    // deprecated Matrix4.translate/scale helpers.
    final target = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, center.dx * (1 - scale))
      ..setEntry(1, 3, center.dy * (1 - scale));
    _zoomTween = Matrix4Tween(begin: _constZoom.value, end: target).animate(
      CurvedAnimation(parent: _zoomAnim, curve: Curves.easeInOut),
    );
    _zoomAnim.forward(from: 0);
  }

  void _zoomIn() {
    HapticFeedback.selectionClick();
    final cur = _constZoom.value.getMaxScaleOnAxis();
    _animateZoomTo((cur + 1.2).clamp(1.0, 4.5));
  }

  void _zoomOut() {
    HapticFeedback.selectionClick();
    final cur = _constZoom.value.getMaxScaleOnAxis();
    _animateZoomTo((cur - 1.2).clamp(1.0, 4.5));
  }

  void _rebuildMock() {
    _items
      ..clear()
      ..addAll(Orbit3MockData.build(count: _populations[_populationIndex]));
  }

  void _rebuildArchetype() {
    _profiles = Orbit3ArchetypeData.build(_archetype);
  }

  void _toggleView() {
    HapticFeedback.selectionClick();
    _resetZoom();
    setState(() {
      _viewMode = _viewMode == Orbit3ViewMode.oneCircle
          ? Orbit3ViewMode.constellation
          : Orbit3ViewMode.oneCircle;
    });
  }

  void _cycleConstMode() {
    HapticFeedback.selectionClick();
    _resetZoom();
    final values = Orbit3ConstellationMode.values;
    setState(() {
      _constMode = values[(_constMode.index + 1) % values.length];
    });
  }

  void _cycleArchetype() {
    HapticFeedback.selectionClick();
    _resetZoom();
    final values = Orbit3Archetype.values;
    setState(() {
      _archetype = values[(_archetype.index + 1) % values.length];
      _rebuildArchetype();
    });
  }

  void _cyclePopulation() {
    setState(() {
      _populationIndex = (_populationIndex + 1) % _populations.length;
      _expanded = false; // a fresh population starts collapsed (two rings)
      _rebuildMock();
    });
  }

  void _toggleNames() {
    HapticFeedback.selectionClick(); // tactile confirmation the toggle fired
    setState(() => _namesVisible = !_namesVisible);
  }

  void _toggleExpand() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
  }

  void _openFriendChat(OrbitFriend friend) {
    Orbit2MockChatScreen.open(
      context,
      friend: Orbit2Friend(friend: friend, tier: AvatarTier.sizeA),
      backgroundPreference: widget.backgroundPreference,
    );
  }

  void _openGroupChat(Orbit2Group group) {
    Orbit2MockChatScreen.openGroup(
      context,
      group: group,
      backgroundPreference: widget.backgroundPreference,
    );
  }

  @override
  Widget build(BuildContext context) {
    final readable = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final media = MediaQuery.of(context);
    final motionEnabled =
        !(media.disableAnimations || media.accessibleNavigation);

    return Orbit2Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Column(
            children: [
              _TopBar(
                readable: readable,
                l10n: l10n,
                isConstellation: _viewMode == Orbit3ViewMode.constellation,
                onToggleView: _toggleView,
                population: _populations[_populationIndex],
                onCyclePopulation: _cyclePopulation,
                namesVisible: _namesVisible,
                onToggleNames: _toggleNames,
              ),
              if (_viewMode == Orbit3ViewMode.constellation)
                _ConstellationLegend(
                  readable: readable,
                  mode: _constMode,
                  onCycleMode: _cycleConstMode,
                  archetype: _archetype,
                  onCycleArchetype: _cycleArchetype,
                ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        // The circle renders at its intrinsic Orbit-parity size
                        // (320 collapsed, larger as rings are revealed) and
                        // scales DOWN only when the grown box exceeds the screen.
                        child: Center(
                          child: _viewMode == Orbit3ViewMode.constellation
                              ? LayoutBuilder(
                                  builder: (context, constraints) {
                                    if (constraints.maxWidth.isFinite &&
                                        constraints.maxHeight.isFinite) {
                                      _viewport = Size(constraints.maxWidth,
                                          constraints.maxHeight);
                                    }
                                    return AnimatedBuilder(
                                      animation: Listenable.merge(
                                          [_twinkle, _constZoom]),
                                      builder: (context, _) {
                                        final zoom = _constZoom.value
                                            .getMaxScaleOnAxis();
                                        return InteractiveViewer(
                                      transformationController: _constZoom,
                                      minScale: 1.0,
                                      maxScale: 4.5,
                                      boundaryMargin:
                                          const EdgeInsets.all(120),
                                      child: FittedBox(
                                        fit: BoxFit.contain,
                                        child: Orbit3Constellation(
                                          userPeerId: widget.userPeerId,
                                          userAvatarBytes:
                                              widget.userAvatarBytes,
                                          profiles: _profiles,
                                          mode: _constMode,
                                          namesVisible: _namesVisible,
                                          motionEnabled: motionEnabled,
                                          searchQuery: _searchQuery,
                                          t: motionEnabled
                                              ? _twinkle.value
                                              : 0.0,
                                          zoom: zoom,
                                          onToggleNames: _toggleNames,
                                          onFriendTap: _openFriendChat,
                                          onGroupTap: _openGroupChat,
                                        ),
                                      ),
                                    );
                                  },
                                    );
                                  },
                                )
                              : FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Orbit3OneCircle(
                                    userPeerId: widget.userPeerId,
                                    userAvatarBytes: widget.userAvatarBytes,
                                    items: _items,
                                    expanded: _expanded,
                                    namesVisible: _namesVisible,
                                    motionEnabled: motionEnabled,
                                    searchQuery: _searchQuery,
                                    onToggleNames: _toggleNames,
                                    onToggleExpand: _toggleExpand,
                                    onFriendTap: _openFriendChat,
                                    onGroupTap: _openGroupChat,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: _Orbit3SearchPill(
                        onChanged: (q) => setState(() => _searchQuery = q),
                      ),
                    ),
                    if (_viewMode == Orbit3ViewMode.constellation)
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: _ZoomControls(
                          readable: readable,
                          onZoomIn: _zoomIn,
                          onZoomOut: _zoomOut,
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.activeTab != null && widget.onSwitchView != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
                  child: FeedNavigationBar(
                    activeTab: widget.activeTab!,
                    onSwitchView: widget.onSwitchView!,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final BackgroundReadableColors readable;
  final AppLocalizations l10n;
  final bool isConstellation;
  final VoidCallback onToggleView;
  final int population;
  final VoidCallback onCyclePopulation;
  final bool namesVisible;
  final VoidCallback onToggleNames;

  const _TopBar({
    required this.readable,
    required this.l10n,
    required this.isConstellation,
    required this.onToggleView,
    required this.population,
    required this.onCyclePopulation,
    required this.namesVisible,
    required this.onToggleNames,
  });

  @override
  Widget build(BuildContext context) {
    // Only a handful of compact chips so nothing clips on a phone — the mode
    // and archetype cyclers live in the legend row below.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 2),
      child: Row(
        children: [
          Text(
            'Orbit3',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: readable.textPrimary,
            ),
          ),
          const SizedBox(width: 10),
          _Chip(
            chipKey: const ValueKey('orbit3-view-toggle'),
            readable: readable,
            icon: isConstellation
                ? Icons.bubble_chart_rounded
                : Icons.blur_circular_rounded,
            text: isConstellation ? 'Map' : 'Circle',
            active: isConstellation,
            onTap: onToggleView,
            semanticLabel:
                isConstellation ? 'Show one circle' : 'Show constellation',
          ),
          const SizedBox(width: 8),
          if (!isConstellation) ...[
            _Chip(
              chipKey: const ValueKey('orbit3-population-cycler'),
              readable: readable,
              icon: Icons.people_alt_rounded,
              text: '$population',
              onTap: onCyclePopulation,
              semanticLabel: 'Population: $population',
            ),
            const SizedBox(width: 8),
          ],
          _Chip(
            chipKey: const ValueKey('orbit3-names-toggle'),
            readable: readable,
            icon:
                namesVisible ? Icons.label_rounded : Icons.label_off_rounded,
            active: namesVisible,
            onTap: onToggleNames,
            semanticLabel:
                namesVisible ? l10n.orbit2_names_hide : l10n.orbit2_names_show,
          ),
          const Spacer(),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primaryAccent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primaryAccent.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                l10n.orbit2_prototype_chip,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1ED760),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A glassy ＋/－ stack for zooming the constellation without pinching (handy on
/// a simulator). Buttons animate [Orbit3Screen]'s zoom so avatars bloom in and
/// the milky way appears.
class _ZoomControls extends StatelessWidget {
  final BackgroundReadableColors readable;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  const _ZoomControls({
    required this.readable,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  Widget _btn(IconData icon, VoidCallback onTap, String label, Key key) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        label: label,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, size: 22, color: readable.iconSecondary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: readable.glassSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: readable.glassBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _btn(Icons.add_rounded, onZoomIn, 'Zoom in',
                  const ValueKey('orbit3-zoom-in')),
              Container(height: 1, width: 26, color: readable.glassBorder),
              _btn(Icons.remove_rounded, onZoomOut, 'Zoom out',
                  const ValueKey('orbit3-zoom-out')),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small pill control in the [_TopBar], matching the names/population chips:
/// an icon (+ optional label), tinted with the brand accent when [active].
class _Chip extends StatelessWidget {
  final BackgroundReadableColors readable;
  final IconData icon;
  final String? text;
  final bool active;
  final VoidCallback onTap;
  final String? semanticLabel;
  final Key? chipKey;

  const _Chip({
    required this.readable,
    required this.icon,
    this.text,
    this.active = false,
    required this.onTap,
    this.semanticLabel,
    this.chipKey,
  });

  @override
  Widget build(BuildContext context) {
    final fill = active
        ? AppColors.primaryAccent.withValues(alpha: 0.14)
        : readable.surfaceSubtle;
    final border = active
        ? AppColors.primaryAccent.withValues(alpha: 0.4)
        : readable.border.withValues(alpha: 0.4);
    final iconColor = active ? AppColors.primaryAccent : readable.iconMuted;
    return GestureDetector(
      key: chipKey,
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: iconColor),
              if (text != null) ...[
                const SizedBox(width: 5),
                Text(
                  text!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: readable.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The control + explanation strip under the top bar in constellation view:
/// the mode + sample-user cyclers, the reciprocity key, and a plain-language
/// note explaining HOW the current map is ordered.
class _ConstellationLegend extends StatelessWidget {
  final BackgroundReadableColors readable;
  final Orbit3ConstellationMode mode;
  final VoidCallback onCycleMode;
  final Orbit3Archetype archetype;
  final VoidCallback onCycleArchetype;

  const _ConstellationLegend({
    required this.readable,
    required this.mode,
    required this.onCycleMode,
    required this.archetype,
    required this.onCycleArchetype,
  });

  ({IconData icon, String label}) get _modeMeta => switch (mode) {
        Orbit3ConstellationMode.zodiac =>
          (icon: Icons.auto_awesome, label: 'Zodiac'),
        Orbit3ConstellationMode.galaxy =>
          (icon: Icons.blur_on, label: 'Galaxy'),
        Orbit3ConstellationMode.gravity =>
          (icon: Icons.public, label: 'Gravity'),
      };

  String get _howOrdered => switch (mode) {
        Orbit3ConstellationMode.zodiac =>
          'Angle = when you met (oldest at the top ↑, going clockwise). Closer to the centre = closer to you now. The gold thread traces your timeline.',
        Orbit3ConstellationMode.galaxy =>
          'The spiral is your timeline — centre = oldest, edge = newest. Talkers lean to one side of the arm, listeners the other. Pinch to zoom into the milky way.',
        Orbit3ConstellationMode.gravity =>
          'Distance from you = how close you are. Bigger star = you chat more. People you were introduced to orbit the friend who introduced them.',
      };

  @override
  Widget build(BuildContext context) {
    final m = _modeMeta;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Chip(
                chipKey: const ValueKey('orbit3-const-mode'),
                readable: readable,
                icon: m.icon,
                text: m.label,
                active: true,
                onTap: onCycleMode,
                semanticLabel: 'Constellation mode: ${m.label}',
              ),
              const SizedBox(width: 8),
              Flexible(
                child: _Chip(
                  chipKey: const ValueKey('orbit3-archetype'),
                  readable: readable,
                  icon: Icons.person_search_rounded,
                  text: archetype.label,
                  onTap: onCycleArchetype,
                  semanticLabel: 'Sample user: ${archetype.label}',
                ),
              ),
              const SizedBox(width: 10),
              _ReciprocityLegend(readable: readable),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 12, color: readable.iconMuted),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  _howOrdered,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.2,
                    color: readable.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The teal → gold → coral temperature key shared by every mode.
class _ReciprocityLegend extends StatelessWidget {
  final BackgroundReadableColors readable;
  const _ReciprocityLegend({required this.readable});

  @override
  Widget build(BuildContext context) {
    final cap = TextStyle(
      fontSize: 8.5,
      color: readable.textMuted,
      fontWeight: FontWeight.w600,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 104,
          height: 7,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: const LinearGradient(colors: [
              Color(0xFF4ECDC4),
              Color(0xFFFFF1C0),
              Color(0xFFFF6B6B),
            ]),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: 104,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                  child: Text('listens',
                      maxLines: 1, overflow: TextOverflow.clip, style: cap)),
              Flexible(
                  child: Text('talks',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      textAlign: TextAlign.right,
                      style: cap)),
            ],
          ),
        ),
      ],
    );
  }
}

/// A search affordance that expands from an icon into a field on tap — a
/// member whose name matches glows in the circle.
class _Orbit3SearchPill extends StatefulWidget {
  final ValueChanged<String> onChanged;
  const _Orbit3SearchPill({required this.onChanged});

  @override
  State<_Orbit3SearchPill> createState() => _Orbit3SearchPillState();
}

class _Orbit3SearchPillState extends State<_Orbit3SearchPill> {
  bool _open = false;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    _controller.clear();
    widget.onChanged('');
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final readable = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 40,
          width: _open ? 186 : 40,
          decoration: BoxDecoration(
            color: readable.glassSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: readable.glassBorder),
          ),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 0,
              maxWidth: 186,
              child: SizedBox(
                width: 186,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (_open) {
                            _close();
                          } else {
                            setState(() => _open = true);
                          }
                        },
                        child: Icon(
                          _open ? Icons.close_rounded : Icons.search_rounded,
                          size: 19,
                          color: readable.iconSecondary,
                        ),
                      ),
                      if (_open) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            autofocus: true,
                            onChanged: widget.onChanged,
                            style: TextStyle(
                                fontSize: 13.5, color: readable.textPrimary),
                            cursorColor: AppColors.primaryAccent,
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: l10n.orbit2_search_hint,
                              hintStyle: TextStyle(
                                fontSize: 13.5,
                                color: readable.placeholderText,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
