import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
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
import '../../application/orbit3_dimension_preferences_use_cases.dart';
import '../../application/orbit3_mock_data.dart';
import '../../domain/orbit3_arch_layout.dart';
import '../../domain/orbit3_connection_profile.dart';
import '../../domain/orbit3_constellation_geometry.dart';
import '../../domain/orbit3_dimension_preferences.dart';
import '../../domain/orbit3_one_circle_layout.dart';
import '../widgets/orbit3_arch_panel.dart';
import '../widgets/orbit3_constellation.dart';
import '../widgets/orbit3_fisheye_prototype.dart';
import '../widgets/orbit3_inner_sky_prototype.dart';
import '../widgets/orbit3_one_circle.dart';

/// Which Orbit3 view is on screen: the packed One Circle, or the new
/// deterministic relationship constellation ("horoscope") fingerprint.
enum Orbit3ViewMode { oneCircle, constellation }

/// Which scalability prototype is mounted. [classic] is the shipped One
/// Circle/Map pairing (default, unchanged). [innerSky] and [fisheye] are the two
/// throwaway directions being compared for "what to do above ~25 friends".
enum Orbit3Lab { classic, innerSky, fisheye }

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

  /// Persists the dimension steppers (avatar/spacing/curve/per-arch) across
  /// launches. Optional + null-default: when null (the const test mounts) the
  /// knobs stay purely in-memory — load/save no-op (plan 169).
  final SecureKeyStore? secureKeyStore;

  const Orbit3Screen({
    super.key,
    this.userPeerId,
    this.userAvatarBytes,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
    this.activeTab,
    this.onSwitchView,
    this.secureKeyStore,
  });

  @override
  State<Orbit3Screen> createState() => _Orbit3ScreenState();
}

class _Orbit3ScreenState extends State<Orbit3Screen>
    with TickerProviderStateMixin {
  // Population milestones: 1 full ring (5), 2 full rings (13), expand-needed (24),
  // many rings (50).
  static const List<int> _populations = [5, 13, 24, 50, 100];

  int _populationIndex = 2;
  final List<Orbit2InnerItem> _items = [];
  bool _namesVisible = true;
  // Classic One Circle overflow now lives on the ARCH: the inner circle is
  // hard-capped at two orbits, the "+N" rides an arch above it, and tapping the
  // arch opens [Orbit3ArchPanel]. `_archOpen` tracks that panel.
  bool _archOpen = false;
  // Live avatar-size multiplier driven by the +/- stepper (Orbit parity = 1.0).
  double _avatarScale = 1.0;
  // Live SPACING multiplier (separate +/- stepper) — scales orbit-ring radii AND
  // arch row pitch, independent of avatar size (168 C1). 1.0 = Orbit parity.
  double _spacingScale = 1.0;
  // Live CURVE multiplier — how deep the arch dome bows (168). 1.0 = default.
  double _curveScale = 1.0;
  // Live avatars-per-arch (168). Capped to what the width fits.
  int _perRow = 7;
  // Drives the unified expanded scroll — arches + circle in ONE surface (167).
  final ScrollController _archScroll = ScrollController();
  // Tags the LOWEST arch row so opening can anchor it just above the Collapse
  // pill (arch-priority expand) rather than pinning the inner circle.
  final GlobalKey _lowestArchKey = GlobalKey();
  String _searchQuery = '';

  // Which scalability prototype is mounted (classic = shipped behaviour).
  Orbit3Lab _lab = Orbit3Lab.classic;

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
    _zoomAnim =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 450),
        )..addListener(() {
          final tw = _zoomTween;
          if (tw != null) _constZoom.value = tw.value;
        });
    // Fire-and-forget: initState is sync, SecureKeyStore.read is async. Render
    // defaults now, then apply any saved dimensions once the read resolves.
    _restoreDimensions();
  }

  /// Loads persisted dimension knobs (plan 169). No-op when no store is wired
  /// (the const test mounts) — the knobs then stay purely in-memory.
  Future<void> _restoreDimensions() async {
    final store = widget.secureKeyStore;
    if (store == null) return;
    final p = await loadOrbit3DimensionPreferences(secureKeyStore: store);
    if (!mounted) return; // screen can unmount during the async read
    setState(() {
      _avatarScale = p.avatarScale;
      _spacingScale = p.spacingScale;
      _curveScale = p.curveScale;
      _perRow = p.perRow;
    });
  }

  /// Persists the current knob values (fire-and-forget; no-op without a store).
  void _persistDimensions() {
    final store = widget.secureKeyStore;
    if (store == null) return;
    saveOrbit3DimensionPreferences(
      secureKeyStore: store,
      prefs: Orbit3DimensionPreferences(
        avatarScale: _avatarScale,
        spacingScale: _spacingScale,
        curveScale: _curveScale,
        perRow: _perRow,
      ),
    );
  }

  /// Restores all four knobs to their defaults AND clears the saved value.
  void _resetDimensions() {
    HapticFeedback.selectionClick();
    setState(() {
      _avatarScale = Orbit3DimensionPreferences.defaults.avatarScale;
      _spacingScale = Orbit3DimensionPreferences.defaults.spacingScale;
      _curveScale = Orbit3DimensionPreferences.defaults.curveScale;
      _perRow = Orbit3DimensionPreferences.defaults.perRow;
    });
    final store = widget.secureKeyStore;
    if (store != null) {
      clearOrbit3DimensionPreferences(secureKeyStore: store);
    }
  }

  @override
  void dispose() {
    _twinkle.dispose();
    _zoomAnim.dispose();
    _constZoom.dispose();
    _archScroll.dispose();
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
    _zoomTween = Matrix4Tween(
      begin: _constZoom.value,
      end: target,
    ).animate(CurvedAnimation(parent: _zoomAnim, curve: Curves.easeInOut));
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
      _archOpen = false;
      _viewMode = _viewMode == Orbit3ViewMode.oneCircle
          ? Orbit3ViewMode.constellation
          : Orbit3ViewMode.oneCircle;
    });
  }

  void _cycleLab() {
    HapticFeedback.selectionClick();
    _resetZoom();
    final values = Orbit3Lab.values;
    setState(() {
      _lab = values[(_lab.index + 1) % values.length];
      // Returning to a fresh lab always starts from the One Circle base state.
      _viewMode = Orbit3ViewMode.oneCircle;
      _archOpen = false;
    });
  }

  String get _labLabel => switch (_lab) {
    Orbit3Lab.classic => 'Classic',
    Orbit3Lab.innerSky => 'Inner+Sky',
    Orbit3Lab.fisheye => 'Fisheye',
  };

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
      _archOpen = false; // a fresh population closes any open arch panel
      _rebuildMock();
    });
  }

  void _toggleNames() {
    HapticFeedback.selectionClick(); // tactile confirmation the toggle fired
    setState(() => _namesVisible = !_namesVisible);
  }

  void _toggleArch() {
    HapticFeedback.selectionClick();
    setState(() => _archOpen = !_archOpen);
    if (_archOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _anchorExpandedScroll());
    }
  }

  // The Collapse pill's height; the lowest arch is parked this far above the
  // bottom so it clears the pill.
  static const double _kArchCollapseClearance = 56.0;

  /// Position the freshly-opened arches (jumpTo → motion-safe).
  ///
  ///  - If everything fits, leave the scroll at rest (circle stays put).
  ///  - If the arches ALONE can fill the viewport, prioritise them: park the
  ///    lowest arch just above the Collapse pill and let the inner circle slide
  ///    below the fold (the user opened the arches to browse them).
  ///  - Otherwise the circle is still needed to fill the space, so bottom-anchor
  ///    it (it stays visible above the pill).
  void _anchorExpandedScroll() {
    if (!_archScroll.hasClients) return;
    final p = _archScroll.position;
    if (p.maxScrollExtent <= 0) return; // all fits → circle stays at rest
    final box = _lowestArchKey.currentContext?.findRenderObject();
    if (box is RenderBox) {
      // Offset that lands the lowest arch's bottom at the viewport's trailing
      // edge. It is positive only when the arches above it overflow the viewport
      // — exactly when we want to drop the circle off-screen and fill with
      // arches. Scroll a touch FURTHER so the lowest arch clears the pill.
      final reveal =
          RenderAbstractViewport.of(box).getOffsetToReveal(box, 1.0).offset;
      if (reveal > 0) {
        p.jumpTo((reveal + _kArchCollapseClearance).clamp(0.0, p.maxScrollExtent));
        return;
      }
    }
    p.jumpTo(p.maxScrollExtent); // bottom-anchor; the circle stays visible
  }

  void _incAvatarSize() {
    HapticFeedback.selectionClick();
    setState(() =>
        _avatarScale = (_avatarScale + 0.2).clamp(0.6, 1.4).toDouble());
    _persistDimensions();
  }

  void _decAvatarSize() {
    HapticFeedback.selectionClick();
    setState(() =>
        _avatarScale = (_avatarScale - 0.2).clamp(0.6, 1.4).toDouble());
    _persistDimensions();
  }

  void _incSpacing() {
    HapticFeedback.selectionClick();
    setState(() =>
        _spacingScale = (_spacingScale + 0.1).clamp(0.7, 1.5).toDouble());
    _persistDimensions();
  }

  void _decSpacing() {
    HapticFeedback.selectionClick();
    setState(() =>
        _spacingScale = (_spacingScale - 0.1).clamp(0.7, 1.5).toDouble());
    _persistDimensions();
  }

  void _incCurve() {
    HapticFeedback.selectionClick();
    setState(() => _curveScale = (_curveScale + 0.5).clamp(0.5, 2.5).toDouble());
    _persistDimensions();
  }

  void _decCurve() {
    HapticFeedback.selectionClick();
    setState(() => _curveScale = (_curveScale - 0.5).clamp(0.5, 2.5).toDouble());
    _persistDimensions();
  }

  void _incPerRow() {
    HapticFeedback.selectionClick();
    setState(() => _perRow = (_perRow + 1).clamp(4, 9).toInt());
    _persistDimensions();
  }

  void _decPerRow() {
    HapticFeedback.selectionClick();
    setState(() => _perRow = (_perRow - 1).clamp(4, 9).toInt());
    _persistDimensions();
  }

  /// A live stepper value: scales read as a one-decimal multiplier (1.0×) and
  /// per-arch reads as a plain count, so each ＋/－ combination is legible (R4).
  static String _fmtScale(double v) => '${v.toStringAsFixed(1)}×';

  /// The pinned ＋/－ steppers in a 2×2 grid: size / spacing | curve / per-arch.
  /// Each shows its CURRENT numeric value so the combinations are comparable.
  Widget _buildSteppers(BackgroundReadableColors readable) {
    _SizeStepper s(IconData icon, String inc, String dec, String incL,
            String decL, String value, VoidCallback onInc, VoidCallback onDec) =>
        _SizeStepper(
          readable: readable,
          headerIcon: icon,
          incKey: ValueKey(inc),
          decKey: ValueKey(dec),
          incLabel: incL,
          decLabel: decL,
          valueLabel: value,
          valueKey: ValueKey(inc.replaceAll('-inc', '-value')),
          onIncrease: onInc,
          onDecrease: onDec,
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Reset-to-default (plan 169) above the size/spacing/curve/per-arch grid.
        _Orbit3ResetPill(readable: readable, onTap: _resetDimensions),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          s(Icons.person_rounded, 'orbit3-avatar-size-inc',
              'orbit3-avatar-size-dec', 'Bigger avatars', 'Smaller avatars',
              _fmtScale(_avatarScale), _incAvatarSize, _decAvatarSize),
          const SizedBox(height: 8),
          s(Icons.unfold_more_rounded, 'orbit3-spacing-inc',
              'orbit3-spacing-dec', 'More spacing', 'Less spacing',
              _fmtScale(_spacingScale), _incSpacing, _decSpacing),
        ]),
        const SizedBox(width: 8),
        Column(mainAxisSize: MainAxisSize.min, children: [
          s(Icons.gesture_rounded, 'orbit3-curve-inc', 'orbit3-curve-dec',
              'More curve', 'Less curve', _fmtScale(_curveScale), _incCurve,
              _decCurve),
          const SizedBox(height: 8),
          s(Icons.groups_rounded, 'orbit3-perrow-inc', 'orbit3-perrow-dec',
              'More per arch', 'Fewer per arch', '$_perRow', _incPerRow,
              _decPerRow),
        ]),
          ],
        ),
      ],
    );
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

  /// The OPEN arch state (167): the inner circle AND every arch row in ONE
  /// continuously-scrollable surface, with pinned collapse / size / search
  /// controls overlaid. Opened anchored on the circle (see [_toggleArch]).
  Widget _buildUnifiedArchScroll(
    BackgroundReadableColors readable,
    bool motionEnabled,
  ) {
    final overflowItems = _items.skip(kOrbit3InnerSeats).toList();
    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, c) {
              final width = c.maxWidth - 24; // matches the Padding(12) inset
              final base = (kOrbit3ArchRowAvatar * _avatarScale)
                  .clamp(20.0, 60.0)
                  .toDouble();
              // Avatars per arch — user-controlled (168), capped to what fits.
              final maxPerRow = (width / (base + 2)).floor();
              final cap = maxPerRow < 4 ? 4 : maxPerRow;
              final perRow = _perRow.clamp(4, cap).toInt();
              // Spacing stepper widens the arch row pitch (168 C1).
              final rowHeight = base + 14.0 * _spacingScale;
              // Curve stepper deepens the arch dome (168); cap at half the row
              // so the centre avatar never climbs out of its row.
              final dip = (base * 0.32 * _curveScale)
                  .clamp(4.0, rowHeight * 0.5)
                  .toDouble();
              final layout = computeOrbit3ArchArcs(
                count: overflowItems.length,
                width: width,
                avatar: base,
                perRow: perRow,
                dip: dip,
              );
              return SingleChildScrollView(
                key: const ValueKey('orbit3-arch-panel'),
                controller: _archScroll,
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: GestureDetector(
                  // Double-tap ANYWHERE on the expanded surface — arches OR the
                  // inner circle — toggles every name label (Request 1). As an
                  // ancestor of every member it shares the gesture arena, so a
                  // single tap still opens that member's chat (one timeout late).
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: _toggleNames,
                  child: ConstrainedBox(
                  constraints: BoxConstraints(
                    // Bottom-anchor the content so the circle stays at the
                    // bottom (open anchored on it) even when it all FITS — not
                    // just when it overflows (167 review nit).
                    minHeight:
                        (c.maxHeight - 56) < 0 ? 0.0 : c.maxHeight - 56,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                    // Arches ABOVE: farthest row first → row 0 is the LAST/lowest
                    // arch, immediately above the gap + circle.
                    for (var i = 0; i < layout.rows.length; i++)
                      Builder(builder: (_) {
                        final r = layout.rows.length - 1 - i;
                        final row = Orbit3ArcRow(
                          key: ValueKey('orbit3-arch-arc-row-$r'),
                          centres: layout.rows[r],
                          rowItems: overflowItems
                              .skip(r * perRow)
                              .take(layout.rows[r].length)
                              .toList(),
                          rowOffset: r * perRow,
                          rowFromBottom: r,
                          width: width,
                          height: rowHeight,
                          avatar: base,
                          readable: readable,
                          motionEnabled: motionEnabled,
                          namesVisible: _namesVisible,
                          onFriendTap: _openFriendChat,
                          onGroupTap: _openGroupChat,
                        );
                        // Tag the LOWEST arch (row 0) so opening anchors it just
                        // above the Collapse pill (arch-priority expand).
                        return r == 0
                            ? KeyedSubtree(key: _lowestArchKey, child: row)
                            : row;
                      }),
                    // First arch hugs the circle like an extension (168).
                    SizedBox(height: 2 * _spacingScale),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        // FittedBox keeps the (spacing-scaled) box SQUARE and
                        // scaled-to-fit so avatars stay on the rings even when
                        // wider spacing grows the box past the pane (168 fix).
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Orbit3OneCircle(
                          userPeerId: widget.userPeerId,
                          userAvatarBytes: widget.userAvatarBytes,
                          items: _items,
                          cappedRings: kOrbit3CollapsedRings,
                          showOverflowNode: false,
                          avatarScale: _avatarScale,
                          ringSpacingScale: _spacingScale,
                          // Inner avatars match the arch avatars; snug box so the
                          // circle is a tight extension below the arches (168).
                          uniformAvatarSize: kOrbit3ArchRowAvatar * _avatarScale,
                          snugBox: true,
                          // Keep the inner circle steady on expand (168 C4).
                          animateEntrance: false,
                          namesVisible: _namesVisible,
                          motionEnabled: motionEnabled,
                          searchQuery: _searchQuery,
                          onToggleNames: _toggleNames,
                          onFriendTap: _openFriendChat,
                          onGroupTap: _openGroupChat,
                          ),
                        ),
                      ),
                    ),
                    // Trailing room so the circle clears the pinned bottom controls.
                    const SizedBox(height: 96),
                    ],
                  ),
                  ),
                ),
              );
            },
          ),
        ),
        // Pinned controls — never scroll.
        Positioned(
          left: 12,
          bottom: 12,
          child: _buildSteppers(readable),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: _Orbit3SearchPill(
            onChanged: (q) => setState(() => _searchQuery = q),
          ),
        ),
        // Pinned collapse pill — bottom-centre, in the band between the lowest
        // arch and the nav bar (between the steppers and the search) (Mod 2).
        Positioned(
          bottom: 12,
          left: 0,
          right: 0,
          child: Center(
            child: Orbit3ArchCollapsePill(
              readable: readable,
              onTap: _toggleArch,
            ),
          ),
        ),
      ],
    );
  }

  /// The COLLAPSED One Circle. When there is overflow it keeps the SAME uniform
  /// avatar size + snug box it had while expanded, so collapsing only hides the
  /// arches — no size jump (Request 3). A "+N" arch chip sits directly above it
  /// (tap to expand). With no overflow it stays the plain Orbit-parity circle.
  Widget _buildCollapsedOneCircle(
    BackgroundReadableColors readable,
    bool motionEnabled,
  ) {
    final overflow = orbit3ArchOverflowCount(_items.length);
    if (overflow <= 0) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Orbit3OneCircle(
          userPeerId: widget.userPeerId,
          userAvatarBytes: widget.userAvatarBytes,
          items: _items,
          // Cap at 2 orbits; overflow lives on the arch, not the in-ring node.
          cappedRings: kOrbit3CollapsedRings,
          showOverflowNode: false,
          avatarScale: _avatarScale,
          ringSpacingScale: _spacingScale,
          namesVisible: _namesVisible,
          motionEnabled: motionEnabled,
          searchQuery: _searchQuery,
          onToggleNames: _toggleNames,
          onFriendTap: _openFriendChat,
          onGroupTap: _openGroupChat,
        ),
      );
    }
    return Padding(
      // Lift the circle so it rests at the SAME height the expanded scroll puts
      // it at, so expanding does not move it (Mod 2). Tuned to match the expanded
      // anchor (measured). The +N chip rides above, where the arches grow in.
      padding: const EdgeInsets.only(bottom: 128),
      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Orbit3ArchBar(count: overflow, onTap: _toggleArch),
        const SizedBox(height: 10),
        // Flexible bounds the circle's height to the room left under the chip so
        // BoxFit.scaleDown fits BOTH axes — on a short/wide surface (landscape,
        // split-view) the snug box can exceed the pane height and a bare
        // FittedBox in a Column would RenderFlex-overflow.
        Flexible(
          child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Orbit3OneCircle(
            userPeerId: widget.userPeerId,
            userAvatarBytes: widget.userAvatarBytes,
            items: _items,
            cappedRings: kOrbit3CollapsedRings,
            showOverflowNode: false,
            avatarScale: _avatarScale,
            ringSpacingScale: _spacingScale,
            // Mirror the expanded inner circle exactly (uniform avatars, snug
            // box, no re-entrance) so collapse keeps the tuned size (R3).
            uniformAvatarSize: kOrbit3ArchRowAvatar * _avatarScale,
            snugBox: true,
            animateEntrance: false,
            namesVisible: _namesVisible,
            motionEnabled: motionEnabled,
            searchQuery: _searchQuery,
            onToggleNames: _toggleNames,
            onFriendTap: _openFriendChat,
            onGroupTap: _openGroupChat,
          ),
        ),
        ),
      ],
      ),
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
                isClassic: _lab == Orbit3Lab.classic,
                labLabel: _labLabel,
                onCycleLab: _cycleLab,
              ),
              if (_viewMode == Orbit3ViewMode.constellation)
                _ConstellationLegend(
                  readable: readable,
                  l10n: l10n,
                  mode: _constMode,
                  onCycleMode: _cycleConstMode,
                  archetype: _archetype,
                  onCycleArchetype: _cycleArchetype,
                ),
              Expanded(
                child: _lab == Orbit3Lab.innerSky
                    ? Orbit3InnerSkyPrototype(
                        userPeerId: widget.userPeerId,
                        userAvatarBytes: widget.userAvatarBytes,
                        items: _items,
                        namesVisible: _namesVisible,
                        motionEnabled: motionEnabled,
                        t: motionEnabled ? _twinkle.value : 0.0,
                        onToggleNames: _toggleNames,
                        onFriendTap: _openFriendChat,
                        onGroupTap: _openGroupChat,
                      )
                    : _lab == Orbit3Lab.fisheye
                    ? Orbit3FisheyePrototype(
                        userPeerId: widget.userPeerId,
                        userAvatarBytes: widget.userAvatarBytes,
                        items: _items,
                        namesVisible: _namesVisible,
                        motionEnabled: motionEnabled,
                        onToggleNames: _toggleNames,
                        onFriendTap: _openFriendChat,
                        onGroupTap: _openGroupChat,
                      )
                    : (_viewMode == Orbit3ViewMode.oneCircle &&
                            _archOpen &&
                            orbit3ArchOverflowCount(_items.length) > 0)
                    ? _buildUnifiedArchScroll(readable, motionEnabled)
                    : Stack(
                        children: [
                          Positioned.fill(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              // The circle renders at its intrinsic Orbit-parity size
                              // (320 collapsed, larger as rings are revealed) and
                              // scales DOWN only when the grown box exceeds the screen.
                              child: AnimatedAlign(
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOutCubic,
                                // With overflow the collapsed circle bottom-
                                // anchors so expanding (which bottom-anchors the
                                // scroll) does not shift it; constellation and the
                                // no-overflow circle stay centred (Mod 2).
                                alignment: (_viewMode ==
                                            Orbit3ViewMode.oneCircle &&
                                        orbit3ArchOverflowCount(_items.length) >
                                            0)
                                    ? Alignment.bottomCenter
                                    : Alignment.center,
                                child: _viewMode == Orbit3ViewMode.constellation
                                    ? LayoutBuilder(
                                        builder: (context, constraints) {
                                          if (constraints.maxWidth.isFinite &&
                                              constraints.maxHeight.isFinite) {
                                            _viewport = Size(
                                              constraints.maxWidth,
                                              constraints.maxHeight,
                                            );
                                          }
                                          return AnimatedBuilder(
                                            animation: Listenable.merge([
                                              _twinkle,
                                              _constZoom,
                                            ]),
                                            builder: (context, _) {
                                              final zoom = _constZoom.value
                                                  .getMaxScaleOnAxis();
                                              return InteractiveViewer(
                                                transformationController:
                                                    _constZoom,
                                                minScale: 1.0,
                                                maxScale: 4.5,
                                                boundaryMargin:
                                                    const EdgeInsets.all(120),
                                                child: FittedBox(
                                                  fit: BoxFit.contain,
                                                  child: Orbit3Constellation(
                                                    userPeerId:
                                                        widget.userPeerId,
                                                    userAvatarBytes:
                                                        widget.userAvatarBytes,
                                                    profiles: _profiles,
                                                    mode: _constMode,
                                                    namesVisible: _namesVisible,
                                                    motionEnabled:
                                                        motionEnabled,
                                                    searchQuery: _searchQuery,
                                                    t: motionEnabled
                                                        ? _twinkle.value
                                                        : 0.0,
                                                    zoom: zoom,
                                                    onToggleNames: _toggleNames,
                                                    onFriendTap:
                                                        _openFriendChat,
                                                    onGroupTap: _openGroupChat,
                                                  ),
                                                ),
                                              );
                                            },
                                          );
                                        },
                                      )
                                    : _buildCollapsedOneCircle(
                                        readable, motionEnabled),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 12,
                            bottom: 12,
                            child: _Orbit3SearchPill(
                              onChanged: (q) =>
                                  setState(() => _searchQuery = q),
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
                          if (_viewMode == Orbit3ViewMode.oneCircle) ...[
                            // The +/- avatar-size stepper (opposite the search
                            // pill, like the constellation zoom stack).
                            Positioned(
                              left: 12,
                              bottom: 12,
                              child: _buildSteppers(readable),
                            ),
                          ],
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
  final bool isClassic;
  final String labLabel;
  final VoidCallback onCycleLab;

  const _TopBar({
    required this.readable,
    required this.l10n,
    required this.isConstellation,
    required this.onToggleView,
    required this.population,
    required this.onCyclePopulation,
    required this.namesVisible,
    required this.onToggleNames,
    required this.isClassic,
    required this.labLabel,
    required this.onCycleLab,
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
            l10n.nav_orbit3,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: readable.textPrimary,
            ),
          ),
          const SizedBox(width: 10),
          // The chips WRAP rather than overflow — adding the lab cycler can never
          // clip the bar on a narrow phone.
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Chip(
                  chipKey: const ValueKey('orbit3-lab-cycler'),
                  readable: readable,
                  icon: Icons.science_rounded,
                  text: labLabel,
                  active: !isClassic,
                  onTap: onCycleLab,
                  semanticLabel: 'Prototype: $labLabel (tap to switch)',
                ),
                if (isClassic)
                  _Chip(
                    chipKey: const ValueKey('orbit3-view-toggle'),
                    readable: readable,
                    icon: isConstellation
                        ? Icons.bubble_chart_rounded
                        : Icons.blur_circular_rounded,
                    text: isConstellation ? 'Map' : 'Circle',
                    active: isConstellation,
                    onTap: onToggleView,
                    semanticLabel: isConstellation
                        ? 'Show one circle'
                        : 'Show constellation',
                  ),
                if (!isConstellation)
                  _Chip(
                    chipKey: const ValueKey('orbit3-population-cycler'),
                    readable: readable,
                    icon: Icons.people_alt_rounded,
                    text: '$population',
                    onTap: onCyclePopulation,
                    semanticLabel: 'Population: $population',
                  ),
                _Chip(
                  chipKey: const ValueKey('orbit3-names-toggle'),
                  readable: readable,
                  icon: namesVisible
                      ? Icons.label_rounded
                      : Icons.label_off_rounded,
                  active: namesVisible,
                  onTap: onToggleNames,
                  semanticLabel: namesVisible
                      ? l10n.orbit2_names_hide
                      : l10n.orbit2_names_show,
                ),
                // The "prototype" badge wraps with the chips (one flex child) so
                // it never competes with them for width on a narrow phone.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 168),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
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
              _btn(
                Icons.add_rounded,
                onZoomIn,
                'Zoom in',
                const ValueKey('orbit3-zoom-in'),
              ),
              Container(height: 1, width: 26, color: readable.glassBorder),
              _btn(
                Icons.remove_rounded,
                onZoomOut,
                'Zoom out',
                const ValueKey('orbit3-zoom-out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact glassy "Reset" pill that restores the dimension steppers to their
/// defaults and clears the saved value (plan 169). Sits above the ＋/－ grid.
class _Orbit3ResetPill extends StatelessWidget {
  final BackgroundReadableColors readable;
  final VoidCallback onTap;
  const _Orbit3ResetPill({required this.readable, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('orbit3-reset-dimensions'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        label: 'Reset dimensions to default',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: readable.glassSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: readable.glassBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded,
                      size: 14, color: readable.iconSecondary),
                  const SizedBox(width: 5),
                  Text(
                    'Reset',
                    style: TextStyle(
                      fontSize: 11.5,
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

/// A glassy ＋/－ stack for tuning a live parameter on the One Circle (avatar
/// SIZE or inter-orbit SPACING) — mirrors [_ZoomControls]. A small [headerIcon]
/// distinguishes the two stacked steppers.
class _SizeStepper extends StatelessWidget {
  final BackgroundReadableColors readable;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final Key incKey;
  final Key decKey;
  final String incLabel;
  final String decLabel;
  final IconData headerIcon;
  final String valueLabel;
  final Key valueKey;

  const _SizeStepper({
    required this.readable,
    required this.onIncrease,
    required this.onDecrease,
    required this.incKey,
    required this.decKey,
    required this.incLabel,
    required this.decLabel,
    required this.headerIcon,
    required this.valueLabel,
    required this.valueKey,
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
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(headerIcon, size: 13, color: readable.iconMuted),
                    const SizedBox(height: 2),
                    // The live value (R4) so each ＋/－ combination is legible.
                    Text(
                      valueLabel,
                      key: valueKey,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.0,
                        fontWeight: FontWeight.w700,
                        color: readable.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 1, width: 26, color: readable.glassBorder),
              _btn(Icons.add_rounded, onIncrease, incLabel, incKey),
              Container(height: 1, width: 26, color: readable.glassBorder),
              _btn(Icons.remove_rounded, onDecrease, decLabel, decKey),
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
  final AppLocalizations l10n;
  final Orbit3ConstellationMode mode;
  final VoidCallback onCycleMode;
  final Orbit3Archetype archetype;
  final VoidCallback onCycleArchetype;

  const _ConstellationLegend({
    required this.readable,
    required this.l10n,
    required this.mode,
    required this.onCycleMode,
    required this.archetype,
    required this.onCycleArchetype,
  });

  ({IconData icon, String label}) get _modeMeta => switch (mode) {
    Orbit3ConstellationMode.zodiac => (
      icon: Icons.auto_awesome,
      label: l10n.orbit3_constellation_zodiac,
    ),
    Orbit3ConstellationMode.galaxy => (
      icon: Icons.blur_on,
      label: l10n.orbit3_constellation_galaxy,
    ),
    Orbit3ConstellationMode.gravity => (
      icon: Icons.public,
      label: l10n.orbit2_template_gravity,
    ),
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
              Icon(
                Icons.info_outline_rounded,
                size: 12,
                color: readable.iconMuted,
              ),
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
    final l10n = AppLocalizations.of(context)!;
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
            gradient: const LinearGradient(
              colors: [Color(0xFF4ECDC4), Color(0xFFFFF1C0), Color(0xFFFF6B6B)],
            ),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: 104,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  l10n.orbit3_listens,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: cap,
                ),
              ),
              Flexible(
                child: Text(
                  l10n.orbit3_talks,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  textAlign: TextAlign.right,
                  style: cap,
                ),
              ),
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
                              fontSize: 13.5,
                              color: readable.textPrimary,
                            ),
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
