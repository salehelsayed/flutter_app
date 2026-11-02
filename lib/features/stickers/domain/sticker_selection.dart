import 'sticker_catalog.dart';

const int kMaxRecentStickers = 16;

/// What the sticker panel shows: the Recent tab, or one group of one pack.
sealed class StickerPanelSelection {
  const StickerPanelSelection();
}

final class RecentStickersSelection extends StickerPanelSelection {
  const RecentStickersSelection();

  @override
  bool operator ==(Object other) => other is RecentStickersSelection;

  @override
  int get hashCode => 0;
}

final class PackGroupSelection extends StickerPanelSelection {
  const PackGroupSelection(this.pack, this.group);

  PackGroupSelection.first(StickerPack pack) : this(pack, pack.groups.first);

  final StickerPack pack;
  final StickerGroup group;

  @override
  bool operator ==(Object other) =>
      other is PackGroupSelection &&
      other.pack.id == pack.id &&
      other.group.id == group.id;

  @override
  int get hashCode => Object.hash(pack.id, group.id);
}

/// Recent ids after sending [stickerId]: newest first, distinct, at most
/// [kMaxRecentStickers].
List<String> withRecentSticker(List<String> recent, String stickerId) => [
  stickerId,
  ...recent.where((id) => id != stickerId),
].take(kMaxRecentStickers).toList(growable: false);
