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
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// 198 "Sculpt & Summon" — the interactive Inner-Circle surface. Owns all
/// SESSION-TRANSIENT state (overflow expansion, labels, the edit session +
/// armed knob, the find query) and the ONLY persisted state (the five geometry
/// knobs, via [SecureKeyStore]). The host ([OrbitWired]) supplies the store, a
/// [resetSignal] it pokes on the Feed→Orbit rising edge, and an
/// [onEditSessionActiveChanged] callback that feeds the feed↔orbit host-swipe
/// yield gate (INV-8).
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

class _InnerCircleInteractiveSurfaceState
    extends State<InnerCircleInteractiveSurface> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _findController = TextEditingController();
  final FocusNode _findFocus = FocusNode();

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
  void dispose() {
    widget.resetSignal?.removeListener(_onResetSignal);
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
    if (!value) _armed = null;
    widget.onEditSessionActiveChanged?.call(value);
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
          // Collapsing removes cv/pr/og — disarm if one of them was armed.
          if (_armed != null && !_collapsedKnobs.contains(_armed)) {
            _armed = null;
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
  }

  void _reset() {
    setState(() => _geometry = OrbitGeometryPrefs.defaults);
    final store = widget.secureKeyStore;
    if (store != null) {
      _persisted = OrbitGeometryPrefs.defaults;
      clearOrbitGeometryPrefs(secureKeyStore: store);
    }
  }

  double _dragSensitivity(OrbitKnob knob, Offset delta) => switch (knob) {
        OrbitKnob.avatarScale => -delta.dy / 90,
        OrbitKnob.spacingScale => delta.dy / 108,
        OrbitKnob.arcWrap => -delta.dy / 90,
        OrbitKnob.maxPerArc => delta.dx / 34,
        OrbitKnob.orbitGap => -delta.dy / 46,
      };

  void _handleDragStart(OrbitKnob knob) {
    setState(() {
      _armed = knob;
      _draggingHandle = true;
      _dragStart = _geometry;
    });
  }

  void _handleDragUpdate(OrbitKnob knob, Offset totalDelta) {
    final d = _dragSensitivity(knob, totalDelta);
    final startValue = _dragStart.valueOf(knob);
    OrbitGeometryPrefs next;
    switch (knob) {
      case OrbitKnob.avatarScale:
        next = _dragStart.copyWith(
            avatarScale: (startValue + d)
                .clamp(OrbitGeometryPrefs.minAvatarScale,
                    OrbitGeometryPrefs.maxAvatarScale)
                .toDouble());
      case OrbitKnob.spacingScale:
        next = _dragStart.copyWith(
            spacingScale: (startValue + d)
                .clamp(OrbitGeometryPrefs.minSpacingScale,
                    OrbitGeometryPrefs.maxSpacingScale)
                .toDouble());
      case OrbitKnob.arcWrap:
        next = _dragStart.copyWith(
            arcWrap: (startValue + d)
                .clamp(OrbitGeometryPrefs.minArcWrap,
                    OrbitGeometryPrefs.maxArcWrap)
                .toDouble());
      case OrbitKnob.maxPerArc:
        next = _dragStart.copyWith(
            maxPerArc: (startValue + d)
                .round()
                .clamp(OrbitGeometryPrefs.minMaxPerArc,
                    OrbitGeometryPrefs.maxMaxPerArc));
      case OrbitKnob.orbitGap:
        next = _dragStart.copyWith(
            orbitGap: (startValue + d)
                .clamp(OrbitGeometryPrefs.minOrbitGap,
                    OrbitGeometryPrefs.maxOrbitGap)
                .toDouble());
    }
    setState(() => _geometry = next);
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
                              editDim: _editing && !_draggingHandle,
                              litIndices: find.litIndices,
                              findActive: find.active,
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

            // Layer 2 — edit overlay (banner, Reset, handles, steppers).
            if (_editing)
              ..._buildEditOverlay(context, l10n, readableColors),

            // Layer 3 — find chip strip + pill (bottom-right).
            ..._buildFind(context, l10n, readableColors, find, bottomInset),
          ],
        );
      },
    );
  }

  List<Widget> _buildEditOverlay(
    BuildContext context,
    AppLocalizations l10n,
    BackgroundReadableColors colors,
  ) {
    final armed = _armed;
    return [
      // Banner.
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
                color: colors.glassSurface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                l10n.orbit_edit_banner,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),

      // Reset (top-left).
      Positioned(
        top: 8,
        left: 8,
        child: Semantics(
          button: true,
          label: l10n.orbit_edit_reset,
          child: TextButton(
            key: const ValueKey('orbit-edit-reset'),
            onPressed: _reset,
            child: Text(l10n.orbit_edit_reset),
          ),
        ),
      ),

      // Handle chips (hosted OUTSIDE the scrolled canvas — survive scroll and
      // canvas rebuilds; TC-198-23/71).
      Positioned(
        bottom: 96,
        left: 0,
        right: 0,
        child: Center(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final knob in _visibleKnobs)
                _HandleChip(
                  key: ValueKey('orbit-handle-${knob.name}'),
                  label: _handleName(l10n, knob),
                  armed: armed == knob,
                  colors: colors,
                  onArm: () => _armKnob(knob),
                  onDragStart: () => _handleDragStart(knob),
                  onDragUpdate: (delta) => _handleDragUpdate(knob, delta),
                  onDragEnd: _handleDragEnd,
                ),
            ],
          ),
        ),
      ),

      // Armed value bubble + −/+ steppers, flanking the nav line.
      if (armed != null)
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StepperButton(
                  key: const ValueKey('orbit-edit-step-decrease'),
                  icon: Icons.remove,
                  semanticsLabel: l10n.orbit_edit_step_decrease(
                      _handleName(l10n, armed)),
                  onTap: () => _step(armed, -1),
                ),
                Container(
                  key: const ValueKey('orbit-edit-value-bubble'),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colors.glassSurface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _formatValue(armed),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                _StepperButton(
                  key: const ValueKey('orbit-edit-step-increase'),
                  icon: Icons.add,
                  semanticsLabel: l10n.orbit_edit_step_increase(
                      _handleName(l10n, armed)),
                  onTap: () => _step(armed, 1),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  List<Widget> _buildFind(
    BuildContext context,
    AppLocalizations l10n,
    BackgroundReadableColors colors,
    OrbitFindResult find,
    double bottomInset,
  ) {
    return [
      // Chip strip (hit-transparent container; only chips are tappable).
      if (find.chips.isNotEmpty)
        Positioned(
          left: 12,
          right: 12,
          bottom: bottomInset + 96,
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
        bottom: bottomInset + 40,
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

class _HandleChip extends StatelessWidget {
  final String label;
  final bool armed;
  final BackgroundReadableColors colors;
  final VoidCallback onArm;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  const _HandleChip({
    super.key,
    required this.label,
    required this.armed,
    required this.colors,
    required this.onArm,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    Offset origin = Offset.zero;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onArm,
        onPanStart: (d) {
          origin = d.globalPosition;
          onDragStart();
        },
        onPanUpdate: (d) => onDragUpdate(d.globalPosition - origin),
        onPanEnd: (_) => onDragEnd(),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: armed
                ? const Color(0x3381E6D9)
                : colors.glassSurface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: armed ? const Color(0xFF81E6D9) : colors.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: armed ? FontWeight.w700 : FontWeight.w500,
              color: armed ? const Color(0xFF81E6D9) : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
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
    final colors = context.backgroundReadableColors;
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: colors.glassSurface,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: colors.textPrimary),
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
