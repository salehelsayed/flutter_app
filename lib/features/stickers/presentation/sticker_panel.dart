import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_app/core/config/custom_stickers_flag.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/stickers/application/custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/application/sticker_media.dart';
import 'package:flutter_app/features/stickers/data/sticker_recents_store.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_app/features/stickers/domain/sticker_catalog.dart';
import 'package:flutter_app/features/stickers/domain/sticker_selection.dart';
import 'package:flutter_app/features/stickers/presentation/custom_sticker_scope.dart';
import 'package:flutter_app/features/stickers/presentation/sticker_labels.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// The panel's height on a tall screen; it takes at most 40% of a short one.
const double kStickerPanelHeight = 300;

/// What the panel needs to show the My stickers tab.
class MyStickersSource {
  const MyStickersSource({
    required this.library,
    required this.onSend,
    required this.onCreate,
  });

  final CustomStickerLibrary library;

  /// Called with the id of the custom sticker the user tapped.
  final ValueChanged<String> onSend;
  final VoidCallback onCreate;
}

/// The sticker picker that takes the keyboard's place under the composer.
class StickerPanel extends StatefulWidget {
  const StickerPanel({
    super.key,
    required this.catalog,
    required this.recentIds,
    required this.onSend,
    this.myStickers,
  });

  final StickerCatalog catalog;

  /// Shows My stickers as the first tab when set.
  final MyStickersSource? myStickers;

  /// Newest first. Ids the catalog does not know (or hides) are skipped.
  final List<String> recentIds;
  final ValueChanged<StickerEntry> onSend;

  @override
  State<StickerPanel> createState() => _StickerPanelState();
}

class _StickerPanelState extends State<StickerPanel> {
  late StickerPanelSelection _selection = _initialSelection();
  StreamSubscription<void>? _customChanges;
  List<CustomSticker> _custom = const [];
  int _customLoads = 0;
  bool _pickedTab = false;
  bool _managing = false;

  @override
  void initState() {
    super.initState();
    _watchCustom();
  }

  @override
  void didUpdateWidget(StickerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.myStickers?.library == widget.myStickers?.library) return;
    _customLoads++;
    unawaited(_customChanges?.cancel());
    _customChanges = null;
    _custom = const [];
    _managing = false;
    if (widget.myStickers == null && _selection is MyStickersSelection) {
      _selection = _initialSelection();
    }
    _watchCustom();
  }

  @override
  void dispose() {
    unawaited(_customChanges?.cancel());
    super.dispose();
  }

  void _watchCustom() {
    final library = widget.myStickers?.library;
    if (library == null) return;
    _customChanges = library.changes.listen((_) => _reloadCustom());
    unawaited(_reloadCustom());
  }

  Future<void> _reloadCustom() async {
    final library = widget.myStickers?.library;
    if (library == null) return;
    final load = ++_customLoads;
    final List<CustomSticker> stickers;
    try {
      stickers = await library.list();
    } on CustomStickerException {
      return;
    }
    if (!mounted || load != _customLoads) return;
    setState(() {
      _custom = stickers;
      if (stickers.isEmpty) _managing = false;
      if (!_pickedTab && stickers.isNotEmpty) {
        _selection = const MyStickersSelection();
      }
    });
  }

  Future<void> _reorder(List<String> ids) async {
    final byId = {for (final s in _custom) s.id: s};
    setState(() => _custom = [for (final id in ids) byId[id]!]);
    try {
      await widget.myStickers!.library.reorder(ids);
    } on CustomStickerException {
      await _reloadCustom();
    }
  }

  void _move(String id, int to) {
    final ids = [for (final s in _custom) s.id]..remove(id);
    unawaited(_reorder(ids..insert(to, id)));
  }

  Future<void> _delete(String id) async {
    setState(() {
      _custom = [..._custom.where((s) => s.id != id)];
      if (_custom.isEmpty) _managing = false;
    });
    try {
      await widget.myStickers!.library.remove(id);
    } on CustomStickerException {
      await _reloadCustom();
    }
  }

  List<StickerPanelSelection> get _tabs => [
    if (widget.myStickers != null) const MyStickersSelection(),
    const RecentStickersSelection(),
    for (final pack in widget.catalog.packs) PackGroupSelection.first(pack),
  ];

  List<StickerEntry> get _recent => [
    for (final id in widget.recentIds) ?widget.catalog.byId(id),
  ];

  StickerPanelSelection _initialSelection() =>
      _recent.isNotEmpty || widget.catalog.packs.isEmpty
      ? const RecentStickersSelection()
      : PackGroupSelection.first(widget.catalog.packs.first);

  int get _tabIndex => switch (_selection) {
    PackGroupSelection(:final pack) => _tabs.indexWhere(
      (tab) => tab is PackGroupSelection && tab.pack.id == pack.id,
    ),
    final other => _tabs.indexOf(other),
  };

  void _select(StickerPanelSelection selection) => setState(() {
    _selection = selection;
    _pickedTab = true;
    _managing = false;
  });

  void _onSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 200) return;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final towardsEnd = (velocity < 0) != rtl;
    final next = _tabIndex + (towardsEnd ? 1 : -1);
    if (next < 0 || next >= _tabs.length) return;
    _select(_tabs[next]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.backgroundReadableColors;
    final selection = _selection;
    return Material(
      color: colors.surfaceBase,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: math.min(
            kStickerPanelHeight,
            MediaQuery.sizeOf(context).height * 0.4,
          ),
          child: Column(
            children: [
              _buildTabs(l10n, colors),
              Divider(height: 1, color: colors.divider),
              if (selection case PackGroupSelection(
                :final pack,
              ) when pack.groups.length > 1)
                _buildGroupFaces(l10n, colors, selection),
              if (_managing) _buildManageBar(l10n, colors),
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('sticker-grid'),
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragEnd: _managing ? null : _onSwipe,
                  child: GridView.count(
                    crossAxisCount: 4,
                    padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 8),
                    children: switch (selection) {
                      MyStickersSelection() => _buildMyStickers(l10n, colors),
                      RecentStickersSelection() => _buildCells(l10n, _recent),
                      PackGroupSelection(:final group) => _buildCells(
                        l10n,
                        group.stickers,
                      ),
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCells(
    AppLocalizations l10n,
    List<StickerEntry> stickers,
  ) => [
    for (final sticker in stickers)
      _StickerCell(
        key: ValueKey('sticker-cell-${sticker.id}'),
        sticker: sticker,
        label: stickerSemanticsLabel(l10n, widget.catalog, sticker.id),
        onTap: () => widget.onSend(sticker),
      ),
  ];

  List<Widget> _buildMyStickers(
    AppLocalizations l10n,
    BackgroundReadableColors colors,
  ) {
    final source = widget.myStickers!;
    final stickers = _custom;
    final ids = [for (final s in stickers) s.id];
    return [
      if (!_managing)
        _CreateTile(
          key: const ValueKey('my-sticker-create'),
          label: l10n.stickers_create,
          colors: colors,
          onTap: source.onCreate,
        ),
      for (final (index, sticker) in stickers.indexed)
        _CustomStickerCell(
          key: ValueKey('my-sticker-${sticker.id}'),
          sticker: sticker,
          label: l10n.stickers_mine_semantics(index + 1, stickers.length),
          managing: _managing,
          colors: colors,
          onTap: () => source.onSend(sticker.id),
          onLongPress: () => setState(() => _managing = true),
          onDelete: () => unawaited(_delete(sticker.id)),
          onDropped: (dragged) => _move(dragged, ids.indexOf(sticker.id)),
          manageActions: {
            if (index > 0)
              CustomSemanticsAction(label: l10n.stickers_move_earlier): () =>
                  _move(sticker.id, index - 1),
            if (index < stickers.length - 1)
              CustomSemanticsAction(label: l10n.stickers_move_later): () =>
                  _move(sticker.id, index + 1),
            CustomSemanticsAction(label: l10n.stickers_delete): () =>
                unawaited(_delete(sticker.id)),
          },
        ),
    ];
  }

  Widget _buildManageBar(
    AppLocalizations l10n,
    BackgroundReadableColors colors,
  ) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 8, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.stickers_drag_to_reorder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
          FilledButton.tonal(
            key: const ValueKey('my-stickers-done'),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () => setState(() => _managing = false),
            child: Text(l10n.you_tags_done),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(AppLocalizations l10n, BackgroundReadableColors colors) {
    final selectedIndex = _tabIndex;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 8),
        children: [
          for (final (index, tab) in _tabs.indexed)
            _TabButton(
              key: ValueKey(switch (tab) {
                MyStickersSelection() => 'sticker-tab-mine',
                RecentStickersSelection() => 'sticker-tab-recent',
                PackGroupSelection(:final pack) => 'sticker-tab-${pack.id}',
              }),
              label: switch (tab) {
                MyStickersSelection() => l10n.stickers_mine,
                RecentStickersSelection() => l10n.stickers_recent,
                PackGroupSelection(:final pack) => stickerPackLabel(
                  l10n,
                  pack.id,
                ),
              },
              selected: index == selectedIndex,
              colors: colors,
              onTap: () => _select(tab),
              child: switch (tab) {
                MyStickersSelection() =>
                  _custom.isEmpty
                      ? Icon(
                          Icons.emoji_emotions_outlined,
                          color: colors.iconPrimary,
                        )
                      : _CustomStickerImage(
                          _custom.first.asset.posterPath ??
                              _custom.first.asset.filePath,
                        ),
                RecentStickersSelection() => Icon(
                  Icons.history_rounded,
                  color: colors.iconPrimary,
                ),
                PackGroupSelection(:final group) => _StickerImage(
                  group.stickers.first,
                ),
              },
            ),
        ],
      ),
    );
  }

  Widget _buildGroupFaces(
    AppLocalizations l10n,
    BackgroundReadableColors colors,
    PackGroupSelection selection,
  ) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 8,
          vertical: 6,
        ),
        children: [
          for (final group in selection.pack.groups)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: Semantics(
                button: true,
                selected: group.id == selection.group.id,
                label: stickerGroupLabel(l10n, group.id),
                onTap: () => _select(PackGroupSelection(selection.pack, group)),
                excludeSemantics: true,
                child: InkResponse(
                  key: ValueKey('sticker-group-${group.id}'),
                  onTap: () =>
                      _select(PackGroupSelection(selection.pack, group)),
                  child: Container(
                    width: 40,
                    height: 40,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: 2,
                        color: group.id == selection.group.id
                            ? colors.iconPrimary
                            : Colors.transparent,
                      ),
                    ),
                    child: ClipOval(child: _StickerImage(group.stickers.first)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final BackgroundReadableColors colors;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 48,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: BorderDirectional(
              bottom: BorderSide(
                width: 2,
                color: selected ? colors.iconPrimary : Colors.transparent,
              ),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _StickerCell extends StatelessWidget {
  const _StickerCell({
    super.key,
    required this.sticker,
    required this.label,
    required this.onTap,
  });

  final StickerEntry sticker;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: _StickerImage(sticker),
        ),
      ),
    );
  }
}

class _CreateTile extends StatelessWidget {
  const _CreateTile({
    super.key,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final BackgroundReadableColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: CustomPaint(
            painter: _DashedBorderPainter(colors.accent),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, color: colors.accent),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        color: colors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(14),
        ).deflate(0.75),
      );
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}

class _CustomStickerCell extends StatelessWidget {
  const _CustomStickerCell({
    super.key,
    required this.sticker,
    required this.label,
    required this.managing,
    required this.colors,
    required this.onTap,
    required this.onLongPress,
    required this.manageActions,
    required this.onDelete,
    required this.onDropped,
  });

  final CustomSticker sticker;
  final String label;
  final bool managing;
  final BackgroundReadableColors colors;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Screen-reader replacements for dragging and the delete badge.
  final Map<CustomSemanticsAction, VoidCallback> manageActions;
  final VoidCallback onDelete;

  /// Called with the id of the sticker dropped onto this one.
  final ValueChanged<String> onDropped;

  @override
  Widget build(BuildContext context) {
    final image = Padding(
      padding: const EdgeInsets.all(4),
      child: _CustomStickerImage(sticker.asset.filePath),
    );
    if (!managing) {
      return Semantics(
        button: true,
        label: label,
        onTap: onTap,
        onLongPress: onLongPress,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(8),
          child: image,
        ),
      );
    }
    final tile = Padding(
      padding: const EdgeInsets.all(4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceRaised,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.border),
              ),
              child: image,
            ),
          ),
          PositionedDirectional(
            top: 0,
            end: 0,
            child: GestureDetector(
              key: ValueKey('my-sticker-delete-${sticker.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: onDelete,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Theme.of(context).colorScheme.onError,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      label: label,
      customSemanticsActions: manageActions,
      excludeSemantics: true,
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) => details.data != sticker.id,
        onAcceptWithDetails: (details) => onDropped(details.data),
        builder: (context, candidates, _) => LongPressDraggable<String>(
          data: sticker.id,
          delay: const Duration(milliseconds: 200),
          feedback: SizedBox.square(
            dimension: 72,
            child: _CustomStickerImage(sticker.asset.filePath),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: tile),
          child: candidates.isEmpty
              ? tile
              : DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(width: 2, color: colors.accent),
                  ),
                  child: tile,
                ),
        ),
      ),
    );
  }
}

class _CustomStickerImage extends StatelessWidget {
  const _CustomStickerImage(this.path);

  final String path;

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      fit: BoxFit.contain,
      cacheWidth: 256,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}

class _StickerImage extends StatelessWidget {
  const _StickerImage(this.sticker);

  final StickerEntry sticker;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      sticker.assetPath,
      fit: BoxFit.contain,
      cacheWidth: 256,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}

/// [StickerPanel] over the bundled catalog and this phone's Recent list.
/// Tapping a sticker moves it to the front of Recent, then calls [onSend].
class BundledStickerPanel extends StatefulWidget {
  const BundledStickerPanel({
    super.key,
    required this.onSend,
    this.recents,
    this.myStickers,
    this.onSendCustom,
  });

  final ValueChanged<StickerEntry> onSend;

  /// Sends the tapped My stickers item by id. With a [CustomStickerScope]
  /// above and no explicit [myStickers], the panel builds its source from
  /// the scope with this callback.
  final ValueChanged<String>? onSendCustom;
  final StickerRecentsStore? recents;

  /// Used only in builds with [kCustomStickersEnabled].
  final MyStickersSource? myStickers;

  @override
  State<BundledStickerPanel> createState() => _BundledStickerPanelState();
}

class _BundledStickerPanelState extends State<BundledStickerPanel> {
  late final StickerRecentsStore _recents =
      widget.recents ?? StickerRecentsStore.shared;
  late final Future<(StickerCatalog, List<String>)> _loaded = (
    loadBundledStickerCatalog(),
    _recents.load(),
  ).wait;
  List<String>? _recentIds;

  MyStickersSource? _myStickers(BuildContext context) {
    if (widget.myStickers case final explicit?) return explicit;
    final onSendCustom = widget.onSendCustom;
    if (onSendCustom == null) return null;
    return myStickersFromScope(context, onSend: onSendCustom);
  }

  void _onSend(StickerEntry sticker) {
    setState(
      () => _recentIds = withRecentSticker(_recentIds ?? const [], sticker.id),
    );
    unawaited(_recents.recordSent(sticker.id));
    widget.onSend(sticker);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(StickerCatalog, List<String>)>(
      future: _loaded,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return SizedBox(
            height: kStickerPanelHeight,
            child: ColoredBox(
              color: context.backgroundReadableColors.surfaceBase,
            ),
          );
        }
        final (catalog, loadedRecentIds) = data;
        return StickerPanel(
          catalog: catalog,
          recentIds: _recentIds ??= loadedRecentIds,
          onSend: _onSend,
          myStickers: kCustomStickersEnabled ? _myStickers(context) : null,
        );
      },
    );
  }
}
