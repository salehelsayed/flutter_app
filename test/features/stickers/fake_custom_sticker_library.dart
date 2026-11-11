import 'dart:async';

import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/features/stickers/application/custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker_asset.dart';

/// In-memory [CustomStickerLibrary] with the v1.2 ordering rules: new items
/// first, duplicates keep their place, reorder takes an exact permutation or
/// throws invalidOrder without changing anything, remove compacts positions.
class FakeCustomStickerLibrary implements CustomStickerLibrary {
  FakeCustomStickerLibrary({Iterable<String> ids = const []}) {
    for (final id in ids.toList().reversed) {
      _admitSync(fakeStickerAsset(id), id: id);
    }
  }

  final _rows = <CustomSticker>[];
  final _changes = StreamController<void>.broadcast(sync: true);
  int _clock = 0;
  int listCalls = 0;
  final reorderCalls = <List<String>>[];

  /// The next reorder call throws invalidOrder, as if the list went stale.
  bool failNextReorder = false;

  List<String> get ids => [for (final row in _rows) row.id];

  @override
  Stream<void> get changes => _changes.stream;

  /// When set, list() waits for it before answering.
  Completer<void>? listGate;

  @override
  Future<List<CustomSticker>> list() async {
    listCalls++;
    final rows = List<CustomSticker>.unmodifiable(_rows);
    final gate = listGate;
    if (gate != null) await gate.future;
    return rows;
  }

  @override
  Future<CustomSticker> admit(NormalizedStickerAsset asset) async {
    final existing = _rows.where((r) => r.asset.sha256Hex == asset.sha256Hex);
    if (existing.isNotEmpty) return existing.first;
    final row = _admitSync(asset, id: 'custom-${_clock + 1}');
    _changes.add(null);
    return row;
  }

  CustomSticker _admitSync(NormalizedStickerAsset asset, {required String id}) {
    _clock++;
    final row = CustomSticker(
      id: id,
      asset: asset,
      createdAtMs: _clock,
      lastUsedAtMs: _clock,
      position: 0,
    );
    _rows.insert(0, row);
    _renumber();
    return row;
  }

  @override
  Future<void> remove(String id) async {
    final before = _rows.length;
    _rows.removeWhere((r) => r.id == id);
    if (_rows.length == before) return;
    _renumber();
    _changes.add(null);
  }

  @override
  Future<void> reorder(List<String> orderedIds) async {
    reorderCalls.add(List.of(orderedIds));
    final current = ids;
    final exact =
        !failNextReorder &&
        orderedIds.length == current.length &&
        orderedIds.toSet().length == orderedIds.length &&
        orderedIds.toSet().containsAll(current);
    failNextReorder = false;
    if (!exact) {
      throw const CustomStickerException(CustomStickerErrorCode.invalidOrder);
    }
    final byId = {for (final r in _rows) r.id: r};
    _rows
      ..clear()
      ..addAll(orderedIds.map((id) => byId[id]!));
    _renumber();
    _changes.add(null);
  }

  @override
  Future<PendingComposerMedia> prepareSend(
    String id, {
    required CustomStickerSendRepresentation representation,
  }) => throw UnimplementedError('not used by the library UI');

  void _renumber() {
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      _rows[i] = CustomSticker(
        id: r.id,
        asset: r.asset,
        createdAtMs: r.createdAtMs,
        lastUsedAtMs: r.lastUsedAtMs,
        position: i,
      );
    }
  }
}

NormalizedStickerAsset fakeStickerAsset(String id, {String? filePath}) =>
    NormalizedStickerAsset(
      filePath: filePath ?? '/nonexistent/$id.webp',
      sha256Hex: 'sha-$id',
      mime: 'image/webp',
      byteLength: 1000,
      width: 512,
      height: 512,
      frameCount: 1,
      durationMs: 0,
    );
