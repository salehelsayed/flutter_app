import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/orbit/application/orbit_find_matches.dart';
import 'package:flutter_app/features/orbit/application/orbit_geometry_prefs_use_cases.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_geometry_prefs.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/orbit_arc_layout.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_edit_handle.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// 198 "Sculpt & Summon" — the interactive Inner-Circle surface. Owns all
/// SESSION-TRANSIENT state (overflow expansion, labels, the edit session +
/// armed knob, the find query) and the ONLY persisted state (the five geometry
/// knobs, via [SecureKeyStore]). The host ([OrbitWired]) supplies the store, a
/// [resetSignal] it pokes on the Feed→Orbit rising edge, and an
/// [onEditSessionActiveChanged] callback that feeds the feed↔orbit host-swipe
/// yield gate (INV-8).
///
/// 198 fidelity — the edit overlay renders the mockup's vocabulary: five
/// glowing [OrbitEditHandle] discs seated ON the orbit geometry (measured
/// canvas origin + pure `orbitHandleAnchor` formulas, re-seated every build,
/// band-hidden but never unmounted off-viewport), a value bubble floating
/// above the armed handle, −/+ steppers flanking the nav band at the bottom
/// corners (with an armed-state bottom re-flow that lifts the find pill and
/// chip strip clear), a 650ms dim flash on stepper presses, and the green
/// terminal banner/Reset chrome.
class InnerCircleInteractiveSurface extends StatefulWidget {
  final String? userPeerId;
  final Uint8List? userAvatarBytes;
  final List<OrbitItem> items;
  final ValueChanged<OrbitFriend> onFriendTap;
  final ValueChanged<OrbitGroup> onGroupTap;

  /// Persists the five geometry knobs. Null ⇒ no persistence (bare-screen pumps).
  final SecureKeyStore? secureKeyStore;

  /// Bubbles the edit-session active flag to the host-swipe yield gate.
  final ValueChanged<bool>? onEditSessionActiveChanged;

  /// Host pokes this on the Feed→Orbit rising edge to reset the transient state.
  final Listenable? resetSignal;

  const InnerCircleInteractiveSurface({
    super.key,
    required this.userPeerId,
    this.userAvatarBytes,
    required this.items,
    required this.onFriendTap,
    required this.onGroupTap,
    this.secureKeyStore,
    this.onEditSessionActiveChanged,
    this.resetSignal,
  });

  @override
  State<InnerCircleInteractiveSurface> createState() =>
      _InnerCircleInteractiveSurfaceState();
}

/// One post-frame measurement of the canvas box: its top-left in SURFACE
/// coordinates plus the scroll offset it was taken at. The column is pinned to
/// the content top, so between measurements only the scroll delta moves the
/// origin — geometry changes ride the anchor formula's own overhang term,
/// which is what makes handle re-seating same-frame (TC-198F-02).
class _CanvasMeasurement {
  final Offset origin;
  final double scrollOffset;

  /// The layout inputs the measurement is valid for — a mismatch in build
  /// schedules a re-measure (constraints/keyboard, items, expansion, knobs).
  final Object signature;

  const _CanvasMeasurement({
    required this.origin,
    required this.scrollOffset,
    required this.signature,
  });
}

class _InnerCircleInteractiveSurfaceState
    extends State<InnerCircleInteractiveSurface> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _findController = TextEditingController();
  final FocusNode _findFocus = FocusNode();
  final GlobalKey _canvasKey = GlobalKey();

  OrbitGeometryPrefs _geometry = OrbitGeometryPrefs.defaults;
  // The last value written to (or read from) the store — write-through change
  // detection compares against this so a no-op step never writes (TC-198-38).
  OrbitGeometryPrefs _persisted = OrbitGeometryPrefs.defaults;

  bool _overflowExpanded = false;
  bool _labelsVisible = false;
  bool _editing = false;
  OrbitKnob? _armed;
  bool _draggingHandle = false;
  OrbitGeometryPrefs _dragStart = OrbitGeometryPrefs.defaults;
  Offset _dragTotal = Offset.zero;

  // 198 fidelity (M9) — a stepper press lifts the dim for 650ms (mockup
  // flashDim). Cancellable so session end / dispose never leaves a timer.
  bool _dimFlash = false;
  Timer? _dimFlashTimer;

  _CanvasMeasurement? _canvasMeasurement;
  bool _measureScheduled = false;
  BoxConstraints? _lastConstraints;

  bool _findOpen = false;

  // Only av/sp affect the always-visible rings; the other three only make sense
  // once the arcs are revealed (TC-198-26).
  static const _collapsedKnobs = [OrbitKnob.avatarScale, OrbitKnob.spacingScale];
  static const _allKnobs = OrbitKnob.values;

  @override
  void initState() {
    super.initState();
    widget.resetSignal?.addListener(_onResetSignal);
    _restoreGeometry();
  }

  @override
  void didUpdateWidget(covariant InnerCircleInteractiveSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetSignal != widget.resetSignal) {
      oldWidget.resetSignal?.removeListener(_onResetSignal);
      widget.resetSignal?.addListener(_onResetSignal);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Fonts / locale / text scale can move the canvas without a constraints
    // change — re-measure to stay seated.
    _scheduleCanvasMeasure();
  }

  @override
  void dispose() {
    widget.resetSignal?.removeListener(_onResetSignal);
    _dimFlashTimer?.cancel();
    _scroll.dispose();
    _findController.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  Future<void> _restoreGeometry() async {
    final store = widget.secureKeyStore;
    if (store == null) return;
    final loaded = await loadOrbitGeometryPrefs(secureKeyStore: store);
    if (!mounted) return;
    setState(() {
      _geometry = loaded;
      _persisted = loaded;
    });
  }

  // 198 TC-198-63 — the extended reset seam: every transient surface state
  // re-derives to its default on the rising edge; the knobs persist untouched.
  void _onResetSignal() {
    if (!mounted) return;
    setState(() {
      _overflowExpanded = false;
      _labelsVisible = false;
      _closeFindInternal();
      if (_editing) _setEditing(false);
      _armed = null;
    });
  }

  void _setEditing(bool value) {
    if (_editing == value) return;
    _editing = value;
    if (!value) {
      _armed = null;
      _dimFlashTimer?.cancel();
      _dimFlash = false;
      _settleInterruptedDrag();
    }
    widget.onEditSessionActiveChanged?.call(value);
  }

  // A handle unmounted mid-drag (session end / badge collapse) disposes its
  // recognizer without onPanEnd/Cancel — settle the bookkeeping and persist
  // here or the dim stays lifted and the dragged value is silently lost.
  void _settleInterruptedDrag() {
    if (!_draggingHandle) return;
    _draggingHandle = false;
    _persist(_geometry);
  }

  List<OrbitKnob> get _visibleKnobs =>
      _overflowExpanded ? _allKnobs : _collapsedKnobs;

  OrbitFindResult get _find => _findActive
      ? computeOrbitFind(
          items: widget.items,
          query: _findController.text,
          geometry: _geometry,
        )
      : OrbitFindResult.inactive;

  bool get _findActive => _findController.text.trim().isNotEmpty;

  // ---- canvas measurement (198 fidelity) ----
  double get _currentOverhang => _overhangFor(_geometry);

  double _overhangFor(OrbitGeometryPrefs g) => _overflowExpanded
      ? orbitArcOverhang(
          memberCount: widget.items.length,
          geometry: g,
          centerY: kOrbitCanvasCenter,
        )
      : 0.0;

  Object _measureSignature(BoxConstraints constraints) =>
      (constraints, widget.items.length, _overflowExpanded, _geometry);

  void _scheduleCanvasMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      _measureCanvasNow();
    });
  }

  // READ-ONLY on _scroll (the single scroll WRITER is the og/cv drag
  // compensation) and runs post-frame only — never during build/layout.
  void _measureCanvasNow() {
    final constraints = _lastConstraints;
    if (constraints == null) return;
    final canvasObj = _canvasKey.currentContext?.findRenderObject();
    final surfaceObj = context.findRenderObject();
    if (canvasObj is! RenderBox || !canvasObj.hasSize) return;
    if (surfaceObj is! RenderBox || !surfaceObj.hasSize) return;
    final next = _CanvasMeasurement(
      origin: canvasObj.localToGlobal(Offset.zero, ancestor: surfaceObj),
      scrollOffset: _scroll.hasClients ? _scroll.offset : 0.0,
      signature: _measureSignature(constraints),
    );
    final prev = _canvasMeasurement;
    if (prev == null ||
        prev.origin != next.origin ||
        prev.scrollOffset != next.scrollOffset ||
        prev.signature != next.signature) {
      setState(() => _canvasMeasurement = next);
    }
  }

  /// The canvas top-left in surface coordinates, corrected for scrolling since
  /// the measurement. Null until the first post-frame measurement lands — the
  /// handle layer stays hidden rather than rendering unseated (TC-198F-09).
  Offset? get _canvasOriginNow {
    final m = _canvasMeasurement;
    if (m == null) return null;
    final scrollNow = _scroll.hasClients ? _scroll.offset : 0.0;
    return m.origin - Offset(0, scrollNow - m.scrollOffset);
  }

  // ---- gesture handlers on the empty background ----
  void _enterEdit() {
    if (_editing) return;
    HapticFeedback.mediumImpact();
    setState(() => _setEditing(true));
  }

  void _toggleLabels() => setState(() => _labelsVisible = !_labelsVisible);

  void _onBackgroundTap() {
    // Tap-away: end edit first, else close find. A plain background tap on the
    // idle surface does nothing.
    if (_editing) {
      setState(() => _setEditing(false));
    } else if (_findOpen || _findActive) {
      setState(_closeFindInternal);
    }
  }

  // During an edit session a node tap acts as tap-away: it ends the session and
  // NEVER opens a chat (TC-198-19). Idle, it routes normally.
  void _onNodeFriendTap(OrbitFriend friend) {
    if (_editing) {
      setState(() => _setEditing(false));
      return;
    }
    widget.onFriendTap(friend);
  }

  void _onNodeGroupTap(OrbitGroup group) {
    if (_editing) {
      setState(() => _setEditing(false));
      return;
    }
    widget.onGroupTap(group);
  }

  void _onBadgeTap() => setState(() {
        _overflowExpanded = !_overflowExpanded;
        if (!_overflowExpanded) {
          // Collapsing removes cv/pr/og — disarm if one of them was armed,
          // and settle a live drag whose handle just unmounted (TC-198F-26).
          if (_armed != null && !_collapsedKnobs.contains(_armed)) {
            _armed = null;
            _settleInterruptedDrag();
          }
        }
      });

  // ---- knob mutation with write-through ----
  void _persist(OrbitGeometryPrefs next) {
    final store = widget.secureKeyStore;
    if (store == null) return;
    if (next == _persisted) return; // change-detection: no write on a no-op
    _persisted = next;
    saveOrbitGeometryPrefs(secureKeyStore: store, prefs: next);
  }

  void _armKnob(OrbitKnob knob) => setState(() => _armed = knob);

  void _step(OrbitKnob knob, int dir) {
    final next = _geometry.stepped(knob, dir);
    setState(() => _geometry = next);
    _persist(next);
    _flashDim();
  }

  // Mockup flashDim (M9): watch the change live for 650ms after every press;
  // re-pressing re-arms the window. Cancelled in _setEditing(false) + dispose.
  void _flashDim() {
    _dimFlashTimer?.cancel();
    setState(() => _dimFlash = true);
    _dimFlashTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() => _dimFlash = false);
    });
  }

  void _reset() {
    setState(() => _geometry = OrbitGeometryPrefs.defaults);
    final store = widget.secureKeyStore;
    if (store != null) {
      _persisted = OrbitGeometryPrefs.defaults;
      clearOrbitGeometryPrefs(secureKeyStore: store);
    }
  }

  // ---- handle drags (delta accumulated in STATE — a rebuild mid-gesture must
  // never reset the origin; cv follows the absolute pointer angle) ----
  void _onHandlePanStart(OrbitKnob knob, DragStartDetails details) {
    setState(() {
      _armed = knob;
      _draggingHandle = true;
      _dragStart = _geometry;
      _dragTotal = Offset.zero;
    });
  }

  void _onHandlePanUpdate(OrbitKnob knob, DragUpdateDetails details) {
    _dragTotal += details.delta;
    final next = _draggedGeometry(knob, details);
    if (next == _geometry) return;
    _compensateScrollForOverhang(knob, next);
    setState(() => _geometry = next);
  }

  OrbitGeometryPrefs _draggedGeometry(
      OrbitKnob knob, DragUpdateDetails details) {
    switch (knob) {
      case OrbitKnob.avatarScale:
        return _dragStart.copyWith(
            avatarScale: (_dragStart.avatarScale - _dragTotal.dy / 90)
                .clamp(OrbitGeometryPrefs.minAvatarScale,
                    OrbitGeometryPrefs.maxAvatarScale)
                .toDouble());
      case OrbitKnob.spacingScale:
        return _dragStart.copyWith(
            spacingScale: (_dragStart.spacingScale + _dragTotal.dy / 108)
                .clamp(OrbitGeometryPrefs.minSpacingScale,
                    OrbitGeometryPrefs.maxSpacingScale)
                .toDouble());
      case OrbitKnob.maxPerArc:
        return _dragStart.copyWith(
            maxPerArc: (_dragStart.maxPerArc + _dragTotal.dx / 34)
                .round()
                .clamp(OrbitGeometryPrefs.minMaxPerArc,
                    OrbitGeometryPrefs.maxMaxPerArc));
      case OrbitKnob.orbitGap:
        // M8 — ÷sp, with sp snapshotted at drag start.
        return _dragStart.copyWith(
            orbitGap: (_dragStart.orbitGap +
                    orbitGapDragDelta(
                        _dragTotal.dy, _dragStart.spacingScale))
                .clamp(OrbitGeometryPrefs.minOrbitGap,
                    OrbitGeometryPrefs.maxOrbitGap)
                .toDouble());
      case OrbitKnob.arcWrap:
        // M7 — the wrap follows the pointer's ANGLE around the live centre.
        final surfaceObj = context.findRenderObject();
        final origin = _canvasOriginNow;
        if (surfaceObj is! RenderBox || origin == null) return _geometry;
        final local = surfaceObj.globalToLocal(details.globalPosition);
        final centre = origin +
            Offset(kOrbitCanvasCenter, kOrbitCanvasCenter + _currentOverhang);
        return _dragStart.copyWith(
            arcWrap: orbitArcWrapFromPointer(centre, local));
    }
  }

  // TC-198-72 — the SINGLE scroll writer: og/cv drags change the overhang and
  // this jump absorbs it, so the circle stays planted under the finger. The
  // measured-origin path only ever READS _scroll.
  void _compensateScrollForOverhang(OrbitKnob knob, OrbitGeometryPrefs next) {
    if (knob != OrbitKnob.orbitGap && knob != OrbitKnob.arcWrap) return;
    if (!_overflowExpanded || !_scroll.hasClients) return;
    final delta = _overhangFor(next) - _overhangFor(_geometry);
    if (delta == 0) return;
    final position = _scroll.position;
    // A short stack has no range to absorb the growth — never force the
    // position out of range (the circle rides the growth; the steppers stay
    // the recovery path). Growth extends the extent by exactly delta, so the
    // clamp below stays reachable after this frame's layout.
    if (delta > 0 && position.maxScrollExtent <= 0) return;
    final target = (_scroll.offset + delta)
        .clamp(0.0, position.maxScrollExtent + (delta > 0 ? delta : 0.0));
    if (target == _scroll.offset) return;
    _scroll.jumpTo(target.toDouble());
  }

  void _handleDragEnd() {
    setState(() => _draggingHandle = false);
    _persist(_geometry);
  }

  // ---- find ----
  void _openFind() {
    setState(() => _findOpen = true);
    _findFocus.requestFocus();
  }

  void _onFindChanged(String _) => setState(() {});

  void _closeFindInternal() {
    _findOpen = false;
    _findController.clear();
    if (_findFocus.hasFocus) _findFocus.unfocus();
  }

  void _openItemFromChip(OrbitFindMatch match) {
    // Chip tap opens the chat, ends any edit session, persists the knobs.
    if (_editing) setState(() => _setEditing(false));
    setState(_closeFindInternal);
    switch (match.item) {
      case OrbitFriendItem(:final friend):
        widget.onFriendTap(friend);
      case OrbitGroupItem(:final group):
        widget.onGroupTap(group);
    }
  }

  // ---- helpers ----
  String _handleName(AppLocalizations l10n, OrbitKnob knob) => switch (knob) {
        OrbitKnob.avatarScale => l10n.orbit_handle_avatar_size,
        OrbitKnob.spacingScale => l10n.orbit_handle_ring_spacing,
        OrbitKnob.arcWrap => l10n.orbit_handle_arc_wrap,
        OrbitKnob.maxPerArc => l10n.orbit_handle_max_per_arc,
        OrbitKnob.orbitGap => l10n.orbit_handle_orbit_gap,
      };

  String _formatValue(OrbitKnob knob) {
    final v = _geometry.valueOf(knob);
    if (knob == OrbitKnob.maxPerArc) return '${v.toInt()}';
    return '${v.toStringAsFixed(1)}×';
  }

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final find = _find;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        _lastConstraints = constraints;
        if (_canvasMeasurement == null ||
            _canvasMeasurement!.signature != _measureSignature(constraints)) {
          _scheduleCanvasMeasure();
        }
        return Stack(
          children: [
            // Layer 1 — scroll view. Inside, the background gesture layer is a
            // SIBLING BEHIND the visualization (NOT an ancestor of the nodes),
            // so node taps fire immediately with no double-tap latency (TC-54)
            // while empty-space long-press / double-tap / tap fall through to it.
            Positioned.fill(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          key: const ValueKey('orbit-inner-circle-background'),
                          behavior: HitTestBehavior.opaque,
                          onLongPressStart:
                              _editing ? null : (_) => _enterEdit(),
                          onDoubleTap: _toggleLabels,
                          onTap: _onBackgroundTap,
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OrbitalVisualization(
                              userPeerId: widget.userPeerId,
                              userAvatarBytes: widget.userAvatarBytes,
                              items: widget.items,
                              onFriendTap: _onNodeFriendTap,
                              onGroupTap: _onNodeGroupTap,
                              geometry: _geometry,
                              overflowExpanded: _overflowExpanded,
                              onBadgeTap: _onBadgeTap,
                              labelsVisible: _labelsVisible,
                              editDim:
                                  _editing && !_draggingHandle && !_dimFlash,
                              editEmphasis: _editing,
                              litIndices: find.litIndices,
                              findActive: find.active,
                              canvasKey: _canvasKey,
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 20),
                              child: Text(
                                l10n.orbit_close_friends,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: readableColors.textMuted,
                                ),
                              ),
                            ),
                            if (widget.items.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  l10n.orbit_inner_circle_empty_hint,
                                  key: const ValueKey(
                                      'orbit-inner-circle-empty-hint'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: readableColors.textMuted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Layer 2 — edit overlay (banner, Reset, anchored handles, bubble,
            // corner steppers).
            if (_editing)
              ..._buildEditOverlay(context, l10n, constraints, bottomInset),

            // Layer 3 — find chip strip + pill (bottom-right). Kept ABOVE the
            // edit overlay for the shared bottom bands (refute C4): the mockup
            // z-order (edit above find) is honored only where spatially
            // disjoint, which the armed-state re-flow guarantees.
            ..._buildFind(context, l10n, readableColors, find, bottomInset),
          ],
        );
      },
    );
  }

  List<Widget> _buildEditOverlay(
    BuildContext context,
    AppLocalizations l10n,
    BoxConstraints constraints,
    double bottomInset,
  ) {
    final armed = _armed;
    return [
      // Banner — green terminal chrome (M11), copy/position unchanged.
      Positioned(
        top: 12,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Center(
            child: Container(
              key: const ValueKey('orbit-edit-banner'),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xB30A0A0F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x591DB954)),
              ),
              child: Text(
                l10n.orbit_edit_banner,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: Color(0xFF1ED760),
                ),
              ),
            ),
          ),
        ),
      ),

      // Reset (top-left) — the dark bordered pill treatment (M11).
      Positioned(
        top: 8,
        left: 8,
        child: Semantics(
          container: true,
          button: true,
          label: l10n.orbit_edit_reset,
          child: GestureDetector(
            key: const ValueKey('orbit-edit-reset'),
            behavior: HitTestBehavior.opaque,
            onTap: _reset,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xB30A0A0F),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x29FFFFFF)),
              ),
              // Excluded so the button announces its label exactly once
              // (TC-198-56) — the Semantics wrapper above already carries it.
              child: ExcludeSemantics(
                child: Text(
                  l10n.orbit_edit_reset,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFC9CED6),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),

      // Geometry-anchored handle layer (M1) + the armed value bubble (M5) —
      // hosted OUTSIDE the scrolled canvas so scroll/rebuild can never kill a
      // live drag; re-seated per build from the measured origin + pure anchor
      // formulas; band-hidden (Offstage, never unmounted) off-viewport.
      Positioned.fill(
        child: ListenableBuilder(
          listenable: _scroll,
          builder: (context, _) {
            final origin = _canvasOriginNow;
            final overhang = _currentOverhang;
            final mirrored =
                Directionality.of(context) == TextDirection.rtl;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (final knob in _visibleKnobs)
                  _buildAnchoredHandle(
                      l10n, knob, origin, overhang, mirrored, constraints),
                if (armed != null && origin != null)
                  _buildValueBubble(
                      armed, origin, overhang, mirrored, constraints),
              ],
            );
          },
        ),
      ),

      // −/+ steppers flank the nav band at the bottom corners while a handle
      // is armed (M6). Physical left/right (house RTL convention,
      // orbit_view_toggle_button.dart) + the bottomInset term (keyboard).
      if (armed != null) ...[
        Positioned(
          left: 22,
          bottom: bottomInset + 28,
          child: _StepperButton(
            key: const ValueKey('orbit-edit-step-decrease'),
            icon: Icons.remove,
            semanticsLabel:
                l10n.orbit_edit_step_decrease(_handleName(l10n, armed)),
            onTap: () => _step(armed, -1),
          ),
        ),
        Positioned(
          right: 22,
          bottom: bottomInset + 28,
          child: _StepperButton(
            key: const ValueKey('orbit-edit-step-increase'),
            icon: Icons.add,
            semanticsLabel:
                l10n.orbit_edit_step_increase(_handleName(l10n, armed)),
            onTap: () => _step(armed, 1),
          ),
        ),
      ],
    ];
  }

  Widget _buildAnchoredHandle(
    AppLocalizations l10n,
    OrbitKnob knob,
    Offset? origin,
    double overhang,
    bool mirrored,
    BoxConstraints constraints,
  ) {
    final anchor = orbitHandleAnchor(knob, _geometry, mirrored: mirrored);
    final measured = origin != null;
    final pos = measured
        ? origin +
            Offset(kOrbitCanvasCenter + anchor.dx,
                kOrbitCanvasCenter + overhang + anchor.dy)
        : Offset.zero;
    // Band-hide on BOTH axes against the surface viewport (never minus
    // viewInsets); unmeasured ⇒ hidden (the first-frame guard, TC-198F-09).
    // Offstage keeps the widget MOUNTED so a live drag survives (TC-198F-04).
    final visible = measured &&
        pos.dx >= 0 &&
        pos.dx <= constraints.maxWidth &&
        pos.dy >= 0 &&
        pos.dy <= constraints.maxHeight;
    const half = OrbitEditHandle.hitTarget / 2;
    return Positioned(
      left: pos.dx - half,
      top: pos.dy - half,
      child: Offstage(
        offstage: !visible,
        child: IgnorePointer(
          ignoring: !visible,
          child: ExcludeSemantics(
            excluding: !visible,
            child: OrbitEditHandle(
              knob: knob,
              label: _handleName(l10n, knob),
              armed: _armed == knob,
              // 203 B3: discs scale live with the avatar-size knob (raw value;
              // the widget clamps). Flows through the drag's own setState.
              scale: _geometry.avatarScale,
              onArm: () => _armKnob(knob),
              onPanStart: (d) => _onHandlePanStart(knob, d),
              onPanUpdate: (d) => _onHandlePanUpdate(knob, d),
              onPanEnd: (_) => _handleDragEnd(),
              onPanCancel: _handleDragEnd,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildValueBubble(
    OrbitKnob armed,
    Offset origin,
    double overhang,
    bool mirrored,
    BoxConstraints constraints,
  ) {
    final anchor = orbitHandleAnchor(armed, _geometry, mirrored: mirrored);
    final pos = origin +
        Offset(kOrbitCanvasCenter + anchor.dx,
            kOrbitCanvasCenter + overhang + anchor.dy);
    // Floats above the armed disc (M5): bottom edge 6px above the disc top,
    // horizontally centred on the handle via the fixed-width Center trick.
    // Clamped into the surface band: the bubble stays PRESENT while its
    // handle is band-hidden (TC-198-71) but never paints past the surface
    // (TC-198F-28).
    final rawBottom = constraints.maxHeight -
        pos.dy +
        OrbitEditHandle.effectiveDiscSize(_geometry.avatarScale) / 2 +
        6;
    final cx = pos.dx.clamp(24.0, constraints.maxWidth - 24.0);
    return Positioned(
      left: cx - 100,
      width: 200,
      bottom: rawBottom.clamp(8.0, constraints.maxHeight - 48.0),
      child: IgnorePointer(
        child: Center(
          child: Container(
            key: const ValueKey('orbit-edit-value-bubble'),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xF0081814),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0x994ECDC4)),
            ),
            child: Text(
              _formatValue(armed),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4ECDC4),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFind(
    BuildContext context,
    AppLocalizations l10n,
    BackgroundReadableColors colors,
    OrbitFindResult find,
    double bottomInset,
  ) {
    // Armed-state bottom re-flow (TC-198F-17/18): the corner steppers own the
    // bottomInset+28 band, so the pill and chip strip lift clear while armed.
    final lifted = _editing && _armed != null;
    return [
      // Chip strip (hit-transparent container; only chips are tappable).
      if (find.chips.isNotEmpty)
        Positioned(
          left: 12,
          right: 12,
          bottom: bottomInset + (lifted ? 144 : 96),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final chip in find.chips)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _FindChip(
                    key: ValueKey('orbit-find-chip-${chip.index}'),
                    label: orbitItemDisplayName(chip.item),
                    provenance: chip.provenance.isArc
                        ? l10n.orbit_chip_provenance_arc(chip.provenance.arcNumber!)
                        : l10n.orbit_chip_provenance_ring(chip.provenance.ringNumber!),
                    colors: colors,
                    onTap: () => _openItemFromChip(chip),
                  ),
                ),
            ],
          ),
        ),

      // Pill (bottom-right): 40px collapsed → ~200px expanded TextField.
      Positioned(
        right: 16,
        bottom: bottomInset + (lifted ? 88 : 40),
        child: _findOpen
            ? Container(
                key: const ValueKey('orbit-find-pill'),
                width: 200,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: colors.glassSurface,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 18, color: colors.iconMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _findController,
                        focusNode: _findFocus,
                        onChanged: _onFindChanged,
                        style: TextStyle(
                            fontSize: 14, color: colors.textPrimary),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: l10n.orbit_find_placeholder,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Semantics(
                container: true,
                button: true,
                label: l10n.orbit_find_pill_semantics,
                child: GestureDetector(
                  key: const ValueKey('orbit-find-pill'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _openFind,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.glassSurface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.search, size: 20, color: colors.iconMuted),
                  ),
                ),
              ),
      ),
    ];
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final String semanticsLabel;
  final VoidCallback onTap;

  const _StepperButton({
    super.key,
    required this.icon,
    required this.semanticsLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Mockup .nav-step: teal-ringed dark glass riding the nav-bar line.
    return Semantics(
      container: true,
      button: true,
      label: semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xE6081411),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x8C4ECDC4)),
          ),
          child: Icon(icon, size: 20, color: const Color(0xFFB9F6E8)),
        ),
      ),
    );
  }
}

class _FindChip extends StatelessWidget {
  final String label;
  final String provenance;
  final BackgroundReadableColors colors;
  final VoidCallback onTap;

  const _FindChip({
    super.key,
    required this.label,
    required this.provenance,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colors.glassSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF81E6D9)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              Text(
                provenance,
                style: TextStyle(fontSize: 9, color: colors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
