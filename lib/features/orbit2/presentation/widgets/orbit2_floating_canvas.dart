import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';

import '../../domain/models/avatar_tier.dart';
import '../../domain/models/orbit2_friend.dart';
import '../../domain/models/orbit2_group.dart';
import '../../domain/models/orbit2_inner_item.dart';
import '../../domain/models/orbit2_layout_template.dart';
import 'floating_avatar.dart';
import 'orbit2_group_node.dart';
import 'orbit2_inner_circle.dart';

const double _kGroupDiameter = 52;

/// Reserved space at the bottom for the dock so the Inner Circle's default
/// position sits just above it.
const double kBottomReserve = 120;

class _Item {
  final String id;
  final AvatarTier tier;
  final Orbit2Friend? friend;
  final Orbit2Group? group;
  const _Item({required this.id, required this.tier, this.friend, this.group});
  bool get isGroup => group != null;
  String get name => friend?.username ?? group!.name;
  double get diameter => isGroup ? _kGroupDiameter : tier.diameter;
  double get radius => diameter / 2;
}

/// Decorative add/remove affordance shown on nodes in Manage mode. Purely
/// visual ([IgnorePointer] at the call site) — the whole node's tap does the work.
class _ManageBadge extends StatelessWidget {
  final bool add;
  const _ManageBadge({required this.add});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: add ? AppColors.primaryAccent : const Color(0xFFE5484D),
        border: Border.all(color: Colors.white, width: 1.4),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
      ),
      child: Icon(add ? Icons.add_rounded : Icons.remove_rounded,
          size: 11, color: Colors.white),
    );
  }
}

/// The unified Orbit2 canvas: the draggable Inner Circle cluster (defaulting to
/// the bottom) plus the free-floating friends AND groups above it. Friends: tap
/// (chat), drag (reposition — dropped nodes are separated so they never
/// overlap), long-press-carry onto the cluster (promote). Inner-circle members:
/// tap (chat) or long-press-drag OUT to remove. Groups: tap (group chat), drag.
/// Double-tap empty space toggles name labels (and the breathing room).
class Orbit2Canvas extends StatefulWidget {
  final List<Orbit2InnerItem> innerItems;
  final String? userPeerId;
  final Uint8List? userAvatarBytes;
  final bool innerExpanded;
  final VoidCallback onToggleInnerExpand;

  final List<Orbit2Friend> floatingFriends;
  final List<Orbit2Group> floatingGroups;
  final Orbit2LayoutTemplate template;
  final int layoutVersion;
  final int innerResetToken;

  final String searchQuery;
  final bool motionEnabled;
  final bool namesVisible;
  final bool manageMode;

  final void Function(Orbit2Friend) onOpenChat;
  final void Function(OrbitFriend) onOpenInnerChat;
  final void Function(Orbit2Group) onOpenGroup;
  final void Function(Orbit2Friend) onPromote;
  final void Function(Orbit2Group) onPromoteGroup;
  final void Function(OrbitFriend) onDemote;
  final void Function(Orbit2Group) onDemoteGroup;
  final VoidCallback onToggleNames;

  const Orbit2Canvas({
    super.key,
    required this.innerItems,
    required this.userPeerId,
    required this.userAvatarBytes,
    required this.innerExpanded,
    required this.onToggleInnerExpand,
    required this.floatingFriends,
    required this.floatingGroups,
    required this.template,
    required this.layoutVersion,
    required this.innerResetToken,
    required this.searchQuery,
    required this.motionEnabled,
    required this.namesVisible,
    required this.manageMode,
    required this.onOpenChat,
    required this.onOpenInnerChat,
    required this.onOpenGroup,
    required this.onPromote,
    required this.onPromoteGroup,
    required this.onDemote,
    required this.onDemoteGroup,
    required this.onToggleNames,
  });

  @override
  State<Orbit2Canvas> createState() => _Orbit2CanvasState();
}

class _Orbit2CanvasState extends State<Orbit2Canvas> {
  final GlobalKey _canvasKey = GlobalKey();

  Map<String, Offset> _homes = {};
  Offset? _innerCenter;
  String? _draggingId;
  String? _carrying;
  Offset _carryPos = Offset.zero;
  OrbitFriend? _carryOut;
  Offset _carryOutPos = Offset.zero;
  bool _innerDragging = false;

  Size? _lastSize;
  Orbit2LayoutTemplate? _lastTemplate;
  int _lastVersion = -1;
  int _lastResetToken = -1;
  bool _lastExpanded = false;
  bool _lastNamesVisible = true;

  // #2 — when names are shown the cluster GROWS and spreads so each member's
  // name fits in the gaps between rings (avatars are also shrunk inside the
  // inner circle in names mode). The radius FRACTIONS are unchanged, so the
  // +N-on-ring geometry (#1) is preserved.
  double get _innerSize => widget.namesVisible
      ? (widget.innerExpanded ? 440 : 360)
      : (widget.innerExpanded ? 320 : 240);
  double get _innerRadius => _innerSize / 2;
  double get _repulsion => _innerRadius + 26;
  double get _minSpacing => widget.namesVisible ? kNamedSpacing : kBareSpacing;

  // Default the cluster to the BOTTOM, just above the dock.
  Offset _defaultInner(Size s) =>
      Offset(s.width / 2, max(_innerRadius + 8, s.height - kBottomReserve - _innerRadius));

  List<_Item> _items() => [
        for (final f in widget.floatingFriends)
          _Item(id: f.peerId, tier: f.tier, friend: f),
        for (final g in widget.floatingGroups)
          _Item(id: g.id, tier: AvatarTier.sizeA, group: g),
      ];

  void _ensureLayout(Size size, List<_Item> items) {
    final ids = items.map((e) => e.id).toSet();
    final haveAll =
        ids.length == _homes.length && ids.every((id) => _homes.containsKey(id));
    final resetInner = _lastResetToken != widget.innerResetToken;
    // A "hard" relayout (re-place EVERY node) only on a deliberate layout change:
    // template switch, size/expand/names change, or an explicit reset/recenter.
    final hardReset = _lastSize != size ||
        _lastTemplate != widget.template ||
        _lastExpanded != widget.innerExpanded ||
        _lastNamesVisible != widget.namesVisible ||
        resetInner;
    final changed =
        hardReset || _lastVersion != widget.layoutVersion || !haveAll;
    if (!changed) {
      _innerCenter ??= _defaultInner(size);
      return;
    }
    if (_innerCenter == null || resetInner) _innerCenter = _defaultInner(size);
    final positions = layoutPositions(
      widget.template,
      canvas: size,
      tiers: items.map((e) => e.tier).toList(),
      exclusionCenter: _innerCenter,
      exclusionRadius: _repulsion,
      minSpacing: _minSpacing,
    );
    if (hardReset) {
      _homes = {for (var i = 0; i < items.length; i++) items[i].id: positions[i]};
    } else {
      // Membership-only churn (promote/demote): KEEP every surviving node where
      // it is (incl. manual drags); only seed genuinely-new ids; drop stale.
      _homes = {
        for (var i = 0; i < items.length; i++)
          items[i].id: _homes[items[i].id] ?? positions[i],
      };
    }
    _lastSize = size;
    _lastTemplate = widget.template;
    _lastVersion = widget.layoutVersion;
    _lastResetToken = widget.innerResetToken;
    _lastExpanded = widget.innerExpanded;
    _lastNamesVisible = widget.namesVisible;
  }

  Offset _clamp(Offset c, double r, Size s) => Offset(
        c.dx.clamp(r, max(r, s.width - r)).toDouble(),
        c.dy.clamp(r, max(r, s.height - r)).toDouble(),
      );

  Offset _clampInner(Offset c, Size s) {
    final m = _innerRadius * 0.45;
    return Offset(
      c.dx.clamp(m, max(m, s.width - m)).toDouble(),
      c.dy.clamp(m, max(m, s.height - m)).toDouble(),
    );
  }

  Offset _renderPos(_Item it, Size size) {
    if (_carrying == it.id) return _carryPos;
    final home = _homes[it.id] ?? Offset(size.width / 2, size.height * 0.4);
    if (_draggingId == it.id) return home;
    return _clamp(repel(home, _innerCenter!, _repulsion), it.radius, size);
  }

  bool get _promotionHover =>
      _carrying != null &&
      _innerCenter != null &&
      (_carryPos - _innerCenter!).distance < _repulsion;

  bool get _removalReady =>
      _carryOut != null &&
      _innerCenter != null &&
      (_carryOutPos - _innerCenter!).distance > _repulsion;

  _Item? _carriedItem(List<_Item> items) {
    for (final it in items) {
      if (it.id == _carrying) return it;
    }
    return null;
  }

  Offset _toCanvas(Offset global, Size size) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return _carryPos;
    return _clamp(box.globalToLocal(global), 20, size);
  }

  bool _matchesSearch(_Item it) {
    final q = widget.searchQuery.trim().toLowerCase();
    return q.isEmpty || it.name.toLowerCase().contains(q);
  }

  int _z(_Item it) {
    if (_carrying == it.id) return 2;
    if (_draggingId == it.id) return 1;
    return 0;
  }

  /// On drop, push the node out of overlap with any neighbour (no merging).
  void _separateOnDrop(_Item it, Size size, List<_Item> items) {
    var pos = _homes[it.id] ?? _renderPos(it, size);
    for (var iter = 0; iter < 40; iter++) {
      var moved = false;
      for (final other in items) {
        if (other.id == it.id) continue;
        final op = _renderPos(other, size);
        final sep = it.radius + other.radius + 8;
        var d = pos - op;
        var dist = d.distance;
        if (dist < 0.001) {
          d = Offset(sep, 0);
          dist = sep;
        }
        if (dist < sep) {
          pos = op + (d / dist) * sep;
          moved = true;
        }
      }
      if (!moved) break;
    }
    setState(() {
      _homes[it.id] = _clamp(pos, it.radius, size);
      _draggingId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final items = _items();
        _ensureLayout(size, items);
        final inner = _innerCenter!;

        final ordered = [...items]..sort((a, b) => a.name.compareTo(b.name));
        final ordinal = {
          for (var i = 0; i < ordered.length; i++) ordered[i].id: i,
        };
        final painted = [...items]..sort((a, b) => _z(a).compareTo(_z(b)));

        return Stack(
          key: _canvasKey,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: widget.onToggleNames,
                child: const SizedBox.expand(),
              ),
            ),
            AnimatedPositioned(
              duration: _innerDragging
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              left: inner.dx - _innerSize / 2,
              top: inner.dy - _innerSize / 2,
              width: _innerSize,
              height: _innerSize,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => setState(() => _innerDragging = true),
                onPanUpdate: (d) => setState(() {
                  _innerCenter = _clampInner(inner + d.delta, size);
                }),
                onPanEnd: (_) => setState(() => _innerDragging = false),
                onPanCancel: () => setState(() => _innerDragging = false),
                child: Orbit2InnerCircle(
                  userPeerId: widget.userPeerId,
                  userAvatarBytes: widget.userAvatarBytes,
                  items: widget.innerItems,
                  size: _innerSize,
                  expanded: widget.innerExpanded,
                  namesVisible: widget.namesVisible,
                  motionEnabled: widget.motionEnabled,
                  manageMode: widget.manageMode,
                  carryActive: _carrying != null,
                  highlighted: _promotionHover,
                  dropLabel: _promotionHover ? _carriedItem(items)?.name : null,
                  carriedOutId: _carryOut?.peerId,
                  searchQuery: widget.searchQuery,
                  onOverflowTap: widget.onToggleInnerExpand,
                  onFriendTap: widget.onOpenInnerChat,
                  onGroupTap: widget.onOpenGroup,
                  onFriendRemove: widget.onDemote,
                  onGroupRemove: widget.onDemoteGroup,
                  onMemberDragStart: (f, g) => setState(() {
                    _carryOut = f;
                    _carryOutPos = _toCanvas(g, size);
                  }),
                  onMemberDragUpdate: (g) =>
                      setState(() => _carryOutPos = _toCanvas(g, size)),
                  onMemberDragEnd: (g) {
                    final remove = _removalReady;
                    final f = _carryOut;
                    setState(() => _carryOut = null);
                    if (remove && f != null) widget.onDemote(f);
                  },
                  onMemberDragCancel: () => setState(() => _carryOut = null),
                ),
              ),
            ),
            for (final it in painted)
              _buildNode(it, size, items, ordinal[it.id] ?? 0),
            if (_carryOut != null) _buildCarriedOut(size),
          ],
        );
      },
    );
  }

  Widget _buildCarriedOut(Size size) {
    final f = _carryOut!;
    final friend = Orbit2Friend(friend: f, tier: AvatarTier.sizeA);
    const d = kFloatingAvatarDiameter;
    return Positioned(
      left: _carryOutPos.dx - d / 2,
      top: _carryOutPos.dy - d / 2,
      width: d,
      height: d,
      child: IgnorePointer(
        child: Opacity(
          opacity: _removalReady ? 1.0 : 0.7,
          child: FloatingAvatar(
            friend: friend,
            lifted: true,
            motionEnabled: widget.motionEnabled,
          ),
        ),
      ),
    );
  }

  Widget _buildNode(_Item it, Size size, List<_Item> items, int ordinal) {
    final readable = context.backgroundReadableColors;
    final center = _renderPos(it, size);
    final d = it.diameter;
    final names = widget.namesVisible;
    final manage = widget.manageMode;
    final footprint = names ? max(d, it.tier.labelMaxWidth) : d;
    final dimmed = !_matchesSearch(it);
    final lifted = _draggingId == it.id || _carrying == it.id;

    final semanticKind = it.isGroup ? 'group' : 'friend';
    final semanticLabel = '${it.name}, $semanticKind';

    return AnimatedPositioned(
      key: ValueKey('floating-pos-${it.id}'),
      duration: lifted ? Duration.zero : const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      left: center.dx - footprint / 2,
      top: center.dy - d / 2,
      width: footprint,
      // Always reserve the label row's height so the box never animates below
      // its content (the children swap instantly; the box would otherwise lag).
      height: d + 30,
      child: Semantics(
        button: true,
        label: semanticLabel,
        sortKey: OrdinalSortKey(ordinal.toDouble()),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // In Manage mode the whole node ADDS to the inner circle; drag/carry
          // are disabled so a tap can never be mistaken for a micro-pan.
          onTap: () {
            if (manage) {
              it.isGroup
                  ? widget.onPromoteGroup(it.group!)
                  : widget.onPromote(it.friend!);
            } else {
              it.isGroup
                  ? widget.onOpenGroup(it.group!)
                  : widget.onOpenChat(it.friend!);
            }
          },
          onPanStart:
              manage ? null : (_) => setState(() => _draggingId = it.id),
          onPanUpdate: manage
              ? null
              : (dd) => setState(() {
                    final next = (_homes[it.id] ?? center) + dd.delta;
                    _homes[it.id] = _clamp(next, it.radius, size);
                  }),
          onPanEnd: manage ? null : (_) => _separateOnDrop(it, size, items),
          onPanCancel:
              manage ? null : () => setState(() => _draggingId = null),
          onLongPressStart: (manage || it.isGroup)
              ? null
              : (_) => setState(() {
                    _carrying = it.id;
                    _carryPos = center;
                  }),
          onLongPressMoveUpdate: (manage || it.isGroup)
              ? null
              : (dd) =>
                  setState(() => _carryPos = _toCanvas(dd.globalPosition, size)),
          onLongPressEnd: (manage || it.isGroup)
              ? null
              : (_) {
                  final promote = _promotionHover;
                  setState(() {
                    if (!promote) _homes[it.id] = _carryPos;
                    _carrying = null;
                  });
                  if (promote) widget.onPromote(it.friend!);
                },
          // A cancelled carry (PointerCancel) skips onLongPressEnd — drop the
          // lifted state so the node isn't stranded mid-carry.
          onLongPressCancel: (manage || it.isGroup)
              ? null
              : () => setState(() => _carrying = null),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: footprint,
                height: d,
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      it.isGroup
                          ? Orbit2GroupNode(
                              key: ValueKey('group-node-${it.id}'),
                              group: it.group!,
                              size: d,
                              dimmed: dimmed,
                              lifted: lifted,
                            )
                          : FloatingAvatar(
                              key: ValueKey('floating-avatar-${it.id}'),
                              friend: it.friend!,
                              dimmed: dimmed,
                              lifted: lifted,
                              motionEnabled: widget.motionEnabled,
                            ),
                      if (manage)
                        const Positioned(
                          top: -3,
                          right: -3,
                          child: IgnorePointer(child: _ManageBadge(add: true)),
                        ),
                    ],
                  ),
                ),
              ),
              if (names)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Opacity(
                      opacity: dimmed ? 0.26 : 1.0,
                      child: _NameLabel(name: it.name, readable: readable),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NameLabel extends StatelessWidget {
  final String name;
  final BackgroundReadableColors readable;
  const _NameLabel({required this.name, required this.readable});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 72),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
      decoration: BoxDecoration(
        color: readable.isLightSurface
            ? Colors.white.withValues(alpha: 0.7)
            : Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: readable.glassBorder.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: readable.textPrimary,
        ),
      ),
    );
  }
}
