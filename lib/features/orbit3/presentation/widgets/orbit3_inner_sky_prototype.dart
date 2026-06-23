import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_group.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_inner_item.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../application/orbit3_profile_adapter.dart';
import '../../domain/orbit3_connection_profile.dart';
import '../../domain/orbit3_constellation_geometry.dart';
import '../../domain/orbit3_one_circle_layout.dart';
import 'orbit3_constellation.dart';
import 'orbit3_one_circle.dart';

/// Prototype A — "Inner Orbit + Sky + Drawer".
///
/// The recommended split: the loved radial circle is HARD-CAPPED at 3 rings (so
/// it never scales to dust), auto-seeded full from closeness order. The "+N"
/// node no longer grows the circle — it LAUNCHES you out to the Sky (the
/// existing constellation) for the ambient whole-network glance. A pull-up
/// DRAWER holds the long tail with search + a "Pin" promote button; long-press a
/// seated member to release it back to the drawer. Visuals-only mock prototype.
class Orbit3InnerSkyPrototype extends StatefulWidget {
  final String? userPeerId;
  final Uint8List? userAvatarBytes;
  final List<Orbit2InnerItem> items;
  final bool namesVisible;
  final bool motionEnabled;

  /// 0..1 twinkle phase for the Sky (held at 0 under reduce-motion).
  final double t;
  final VoidCallback? onToggleNames;
  final ValueChanged<OrbitFriend>? onFriendTap;
  final ValueChanged<Orbit2Group>? onGroupTap;

  const Orbit3InnerSkyPrototype({
    super.key,
    required this.userPeerId,
    this.userAvatarBytes,
    required this.items,
    this.namesVisible = true,
    this.motionEnabled = true,
    this.t = 0.0,
    this.onToggleNames,
    this.onFriendTap,
    this.onGroupTap,
  });

  @override
  State<Orbit3InnerSkyPrototype> createState() =>
      _Orbit3InnerSkyPrototypeState();
}

class _Orbit3InnerSkyPrototypeState extends State<Orbit3InnerSkyPrototype> {
  // Members the user explicitly PINNED into the Inner Orbit (front of order).
  final List<String> _pinned = [];
  // Members the user RELEASED out of the Inner Orbit (pushed to the tail/drawer).
  final Set<String> _released = {};

  bool _launched = false; // false = Inner Orbit, true = Sky
  Orbit3ConstellationMode _mode = Orbit3ConstellationMode.gravity;
  String _drawerQuery = '';
  final TransformationController _zoom = TransformationController();

  // 3 full Orbit-parity rings: 5 + 8 + 11 = 24 seats. Everyone else is drawer.
  int get _innerCap =>
      orbit3RingCapacity(0) + orbit3RingCapacity(1) + orbit3RingCapacity(2);

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  /// Pinned-first, then closeness order (minus released), then released at the
  /// tail — so the first [_innerCap] seat the Inner Orbit and the rest fall into
  /// the drawer.
  List<Orbit2InnerItem> get _ordered {
    final byId = {for (final it in widget.items) it.id: it};
    final pinnedSet = _pinned.toSet();
    final pinnedItems = [
      for (final id in _pinned)
        if (byId[id] != null) byId[id]!,
    ];
    final auto = [
      for (final it in widget.items)
        if (!pinnedSet.contains(it.id) && !_released.contains(it.id)) it,
    ];
    final releasedItems = [
      for (final it in widget.items)
        if (_released.contains(it.id) && !pinnedSet.contains(it.id)) it,
    ];
    return [...pinnedItems, ...auto, ...releasedItems];
  }

  List<Orbit2InnerItem> get _drawerItems {
    final tail = _ordered.skip(_innerCap).toList();
    final q = _drawerQuery.trim().toLowerCase();
    if (q.isEmpty) return tail;
    return tail
        .where((it) => it.displayName.toLowerCase().contains(q))
        .toList();
  }

  void _launch() {
    HapticFeedback.selectionClick();
    _zoom.value = Matrix4.identity();
    setState(() => _launched = true);
  }

  void _returnToInner() {
    HapticFeedback.selectionClick();
    setState(() => _launched = false);
  }

  void _cycleMode() {
    HapticFeedback.selectionClick();
    final v = Orbit3ConstellationMode.values;
    setState(() => _mode = v[(_mode.index + 1) % v.length]);
  }

  void _pin(Orbit2InnerItem it) {
    HapticFeedback.mediumImpact();
    setState(() {
      _released.remove(it.id);
      _pinned.remove(it.id);
      _pinned.insert(0, it.id);
    });
    _snack('${it.displayName} pinned to your Inner Orbit');
  }

  void _release(Orbit2InnerItem it) {
    final l10n = AppLocalizations.of(context)!;
    HapticFeedback.mediumImpact();
    setState(() {
      _pinned.remove(it.id);
      _released.add(it.id);
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          content: Text(l10n.orbit3_released_to_drawer(it.displayName)),
          action: SnackBarAction(
            label: l10n.feed_undo,
            onPressed: () => setState(() => _released.remove(it.id)),
          ),
        ),
      );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1400),
          behavior: SnackBarBehavior.floating,
          content: Text(msg),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final readable = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final overflow = (_ordered.length - _innerCap).clamp(0, 9999);

    return Stack(
      children: [
        // The active surface — Inner Orbit or Sky.
        Positioned.fill(
          child: Padding(
            // Leave room for the peeking drawer at the bottom.
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            child: _launched ? _buildSky(readable) : _buildInner(readable),
          ),
        ),

        // Sky controls (mode + back) only while launched.
        if (_launched)
          Positioned(
            left: 12,
            top: 8,
            right: 12,
            child: Row(
              children: [
                _Pill(
                  readable: readable,
                  icon: Icons.keyboard_arrow_left_rounded,
                  label: l10n.orbit3_inner_short,
                  onTap: _returnToInner,
                  keyValue: const ValueKey('proto-a-return-inner'),
                ),
                const SizedBox(width: 8),
                _Pill(
                  readable: readable,
                  icon: _modeIcon,
                  label: _modeLabel,
                  active: true,
                  onTap: _cycleMode,
                  keyValue: const ValueKey('proto-a-sky-mode'),
                ),
                const Spacer(),
                Flexible(
                  child: _GlassHint(
                    readable: readable,
                    text: 'Whole network · pinch to fly in',
                  ),
                ),
              ],
            ),
          ),

        // The pull-up drawer — present in BOTH surfaces.
        _buildDrawer(readable, overflow, l10n),
      ],
    );
  }

  IconData get _modeIcon => switch (_mode) {
    Orbit3ConstellationMode.zodiac => Icons.auto_awesome,
    Orbit3ConstellationMode.galaxy => Icons.blur_on,
    Orbit3ConstellationMode.gravity => Icons.public,
  };

  String get _modeLabel => switch (_mode) {
    Orbit3ConstellationMode.zodiac => 'Zodiac',
    Orbit3ConstellationMode.galaxy => 'Galaxy',
    Orbit3ConstellationMode.gravity => 'Gravity',
  };

  Widget _buildInner(BackgroundReadableColors readable) {
    return Center(
      child: FittedBox(
        // scaleDown only ever SHRINKS to fit a narrow phone; it never blows the
        // circle up, so avatars keep their full Orbit-parity size.
        fit: BoxFit.scaleDown,
        child: Orbit3OneCircle(
          userPeerId: widget.userPeerId,
          userAvatarBytes: widget.userAvatarBytes,
          items: _ordered,
          cappedRings: 3,
          namesVisible: widget.namesVisible,
          motionEnabled: widget.motionEnabled,
          onToggleNames: widget.onToggleNames,
          onToggleExpand: _launch, // "+N" launches to Sky, never grows rings
          onMemberLongPress: _release,
          onFriendTap: widget.onFriendTap,
          onGroupTap: widget.onGroupTap,
        ),
      ),
    );
  }

  Widget _buildSky(BackgroundReadableColors readable) {
    final profiles = orbit3ProfilesFromItems(widget.items);
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 360,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 360,
        );
        return AnimatedBuilder(
          animation: _zoom,
          builder: (context, _) {
            final z = _zoom.value.getMaxScaleOnAxis();
            return InteractiveViewer(
              transformationController: _zoom,
              minScale: 1.0,
              maxScale: 4.5,
              boundaryMargin: const EdgeInsets.all(120),
              child: SizedBox(
                width: viewport.width,
                height: viewport.height,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Orbit3Constellation(
                    userPeerId: widget.userPeerId,
                    userAvatarBytes: widget.userAvatarBytes,
                    profiles: profiles,
                    mode: _mode,
                    namesVisible: widget.namesVisible,
                    motionEnabled: widget.motionEnabled,
                    t: widget.motionEnabled ? widget.t : 0.0,
                    zoom: z,
                    onToggleNames: widget.onToggleNames,
                    onFriendTap: widget.onFriendTap,
                    onGroupTap: widget.onGroupTap,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDrawer(
    BackgroundReadableColors readable,
    int overflow,
    AppLocalizations l10n,
  ) {
    final items = _drawerItems;
    return DraggableScrollableSheet(
      key: const ValueKey('proto-a-drawer'),
      initialChildSize: 0.13,
      minChildSize: 0.13,
      maxChildSize: 0.82,
      snap: true,
      snapSizes: const [0.13, 0.82],
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: readable.glassSurface,
                border: Border(top: BorderSide(color: readable.glassBorder)),
              ),
              // ONE scrollable — handle, header, search, then rows. No
              // Column/Expanded, so the sheet can never overflow at peek height.
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: readable.iconMuted.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.people_outline_rounded,
                          size: 16,
                          color: readable.iconSecondary,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          l10n.orbit3_all_friends,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: readable.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '· +$overflow',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: readable.textMuted,
                          ),
                        ),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            l10n.orbit3_drag_up_to_search,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: readable.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: TextField(
                      onChanged: (q) => setState(() => _drawerQuery = q),
                      style: TextStyle(
                        fontSize: 14,
                        color: readable.textPrimary,
                      ),
                      cursorColor: AppColors.primaryAccent,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: readable.iconMuted,
                        ),
                        hintText: l10n.orbit3_find_anyone,
                        hintStyle: TextStyle(
                          fontSize: 14,
                          color: readable.placeholderText,
                        ),
                        filled: true,
                        fillColor: readable.surfaceSubtle,
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 30,
                        horizontal: 16,
                      ),
                      child: Text(
                        overflow == 0
                            ? 'Everyone fits in your Inner Orbit'
                            : 'No matches',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: readable.textMuted,
                        ),
                      ),
                    )
                  else
                    for (var i = 0; i < items.length; i++)
                      _DrawerRow(
                        item: items[i],
                        index: i,
                        readable: readable,
                        onPin: () => _pin(items[i]),
                        onOpen: () {
                          final it = items[i];
                          if (it.isGroup) {
                            widget.onGroupTap?.call(it.group!);
                          } else {
                            widget.onFriendTap?.call(it.friend!);
                          }
                        },
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A single long-tail row in the drawer: avatar + name + faux preview + a "Pin"
/// promote button on the right.
class _DrawerRow extends StatelessWidget {
  final Orbit2InnerItem item;
  final int index;
  final BackgroundReadableColors readable;
  final VoidCallback onPin;
  final VoidCallback onOpen;

  const _DrawerRow({
    required this.item,
    required this.index,
    required this.readable,
    required this.onPin,
    required this.onOpen,
  });

  static const List<String> _previews = [
    'coffee soon?',
    'sent a photo',
    'voice message',
    'you: sounds good',
    'haha yeah',
    'see you there',
    'thanks!',
    'let me check',
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final preview = _previews[orbit3Hash(item.id, 3) % _previews.length];
    final Widget avatar = item.isGroup
        ? Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.tealAccent.withValues(alpha: 0.9),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.group_rounded,
              size: 22,
              color: Colors.black87,
            ),
          )
        : OrbitalAvatar(
            peerId: item.friend!.peerId,
            size: 42,
            globalIndex: index,
            motionEnabled: false,
            borderWidth: 1,
            borderColor: readable.border.withValues(alpha: 0.2),
            semanticLabel: l10n.orbit2_open_chat_with(item.displayName),
          );

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: readable.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: readable.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onPin,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryAccent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.primaryAccent.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 15,
                      color: Color(0xFF1ED760),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.orbit3_pin,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1ED760),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small glass pill control (back / mode cyclers in Sky).
class _Pill extends StatelessWidget {
  final BackgroundReadableColors readable;
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Key? keyValue;

  const _Pill({
    required this.readable,
    required this.icon,
    required this.label,
    this.active = false,
    required this.onTap,
    this.keyValue,
  });

  @override
  Widget build(BuildContext context) {
    final fill = active
        ? AppColors.primaryAccent.withValues(alpha: 0.16)
        : readable.glassSurface;
    final border = active
        ? AppColors.primaryAccent.withValues(alpha: 0.45)
        : readable.glassBorder;
    return GestureDetector(
      key: keyValue,
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: active
                      ? AppColors.primaryAccent
                      : readable.iconSecondary,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: readable.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassHint extends StatelessWidget {
  final BackgroundReadableColors readable;
  final String text;
  const _GlassHint({required this.readable, required this.text});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: readable.glassSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: readable.glassBorder),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: readable.textMuted),
          ),
        ),
      ),
    );
  }
}
