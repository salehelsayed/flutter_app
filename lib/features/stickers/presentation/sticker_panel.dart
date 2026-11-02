import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/stickers/application/sticker_media.dart';
import 'package:flutter_app/features/stickers/data/sticker_recents_store.dart';
import 'package:flutter_app/features/stickers/domain/sticker_catalog.dart';
import 'package:flutter_app/features/stickers/domain/sticker_selection.dart';
import 'package:flutter_app/features/stickers/presentation/sticker_labels.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// The panel's height on a tall screen; it takes at most 40% of a short one.
const double kStickerPanelHeight = 300;

/// The sticker picker that takes the keyboard's place under the composer.
class StickerPanel extends StatefulWidget {
  const StickerPanel({
    super.key,
    required this.catalog,
    required this.recentIds,
    required this.onSend,
  });

  final StickerCatalog catalog;

  /// Newest first. Ids the catalog does not know (or hides) are skipped.
  final List<String> recentIds;
  final ValueChanged<StickerEntry> onSend;

  @override
  State<StickerPanel> createState() => _StickerPanelState();
}

class _StickerPanelState extends State<StickerPanel> {
  late StickerPanelSelection _selection = _initialSelection();

  List<StickerPanelSelection> get _tabs => [
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
    RecentStickersSelection() => 0,
    PackGroupSelection(:final pack) =>
      1 + widget.catalog.packs.indexWhere((p) => p.id == pack.id),
  };

  void _select(StickerPanelSelection selection) =>
      setState(() => _selection = selection);

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
    final stickers = switch (selection) {
      RecentStickersSelection() => _recent,
      PackGroupSelection(:final group) => group.stickers,
    };
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
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('sticker-grid'),
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragEnd: _onSwipe,
                  child: GridView.count(
                    crossAxisCount: 4,
                    padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 8),
                    children: [
                      for (final sticker in stickers)
                        _StickerCell(
                          key: ValueKey('sticker-cell-${sticker.id}'),
                          sticker: sticker,
                          label: stickerSemanticsLabel(l10n, sticker.id),
                          onTap: () => widget.onSend(sticker),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
                RecentStickersSelection() => 'sticker-tab-recent',
                PackGroupSelection(:final pack) => 'sticker-tab-${pack.id}',
              }),
              label: switch (tab) {
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
  const BundledStickerPanel({super.key, required this.onSend, this.recents});

  final ValueChanged<StickerEntry> onSend;
  final StickerRecentsStore? recents;

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
        );
      },
    );
  }
}
