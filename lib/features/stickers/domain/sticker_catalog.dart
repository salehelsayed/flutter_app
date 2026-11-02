import 'dart:convert';

/// Packs marked `test_only` in packs.json ship only in builds made with
/// `--dart-define=MKNOON_TEST_ONLY_STICKERS=true`.
const bool kIncludeTestOnlyStickers = bool.fromEnvironment(
  'MKNOON_TEST_ONLY_STICKERS',
);

const String kStickerPacksAssetPath = 'assets/stickers/packs.json';

enum StickerPackStatus { ship, testOnly }

final class StickerEntry {
  const StickerEntry({required this.id, required this.assetPath});

  final String id;
  final String assetPath;
}

final class StickerGroup {
  const StickerGroup({
    required this.id,
    required this.order,
    required this.stickers,
  });

  final String id;
  final int order;
  final List<StickerEntry> stickers;
}

final class StickerPack {
  const StickerPack({
    required this.id,
    required this.order,
    required this.status,
    required this.groups,
  });

  final String id;
  final int order;
  final StickerPackStatus status;
  final List<StickerGroup> groups;
}

final class StickerCatalog {
  StickerCatalog._(this.packs)
    : _byId = {
        for (final pack in packs)
          for (final group in pack.groups)
            for (final sticker in group.stickers) sticker.id: sticker,
      };

  /// Parses packs.json. Throws [FormatException] on a malformed list: it is a
  /// bundled asset, so a bad shape is a build defect, not user input.
  factory StickerCatalog.parse(String raw, {required bool includeTestOnly}) {
    final root = _map(jsonDecode(raw));
    final packs = [
      for (final rawPack in _list(root['packs'])) _parsePack(_map(rawPack)),
    ].where((p) => includeTestOnly || p.status != StickerPackStatus.testOnly);
    return StickerCatalog._(
      List.unmodifiable(packs.toList()..sort(_byOrder((p) => p.order))),
    );
  }

  final List<StickerPack> packs;
  final Map<String, StickerEntry> _byId;

  StickerEntry? byId(String id) => _byId[id];
}

/// The group segment of a pack-list id (`<pack>.<group>.<name>`), or null.
String? stickerGroupIdOf(String stickerId) {
  final parts = stickerId.split('.');
  return parts.length == 3 ? parts[1] : null;
}

StickerPack _parsePack(Map<String, Object?> raw) {
  final groups = [
    for (final rawGroup in _list(raw['groups'])) _parseGroup(_map(rawGroup)),
  ]..sort(_byOrder((g) => g.order));
  return StickerPack(
    id: _string(raw['id']),
    order: _int(raw['order']),
    status: switch (raw['status']) {
      'ship' => StickerPackStatus.ship,
      'test_only' => StickerPackStatus.testOnly,
      final other => throw FormatException(
        'unknown sticker pack status $other',
      ),
    },
    groups: List.unmodifiable(groups),
  );
}

StickerGroup _parseGroup(Map<String, Object?> raw) {
  final ordered = [
    for (final rawSticker in _list(raw['stickers']))
      (_map(rawSticker)['order'], _map(rawSticker)),
  ]..sort(_byOrder((entry) => _int(entry.$1)));
  return StickerGroup(
    id: _string(raw['id']),
    order: _int(raw['order']),
    stickers: List.unmodifiable([
      for (final (_, sticker) in ordered)
        StickerEntry(
          id: _string(sticker['id']),
          assetPath: _string(sticker['file']),
        ),
    ]),
  );
}

int Function(T, T) _byOrder<T>(int Function(T) order) =>
    (a, b) => order(a).compareTo(order(b));

Map<String, Object?> _map(Object? value) => value is Map<String, Object?>
    ? value
    : throw const FormatException('sticker pack list: expected an object');

List<Object?> _list(Object? value) => value is List<Object?>
    ? value
    : throw const FormatException('sticker pack list: expected a list');

String _string(Object? value) => value is String && value.isNotEmpty
    ? value
    : throw const FormatException('sticker pack list: expected a string');

int _int(Object? value) => value is int
    ? value
    : throw const FormatException('sticker pack list: expected an int');
