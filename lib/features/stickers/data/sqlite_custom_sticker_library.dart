import 'dart:io';

import 'package:flutter_app/core/config/custom_stickers_flag.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/features/stickers/application/custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker_asset.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// Tests-first API scaffold, deliberately without storage behavior.
///
/// Root captures the behavioral RED before implementing or wiring this class.
final class SqliteCustomStickerLibrary implements CustomStickerLibrary {
  SqliteCustomStickerLibrary({
    required Database db,
    required Directory documentsDirectory,
    required Directory temporaryDirectory,
    required Future<bool> Function() mayUseAccount,
    bool enabled = kCustomStickersEnabled,
    Future<NormalizedStickerAsset> Function(
      NormalizedStickerAsset input, {
      required Directory temporaryDirectory,
    })?
    normalizeAsset,
  });

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<List<CustomSticker>> list() async => const <CustomSticker>[];

  @override
  Future<CustomSticker> admit(NormalizedStickerAsset asset) async =>
      throw UnimplementedError('Custom sticker admission');

  @override
  Future<void> remove(String id) async =>
      throw UnimplementedError('Custom sticker removal');

  @override
  Future<void> reorder(List<String> orderedIds) async =>
      throw UnimplementedError('Custom sticker ordering');

  @override
  Future<PendingComposerMedia> prepareSend(
    String id, {
    required CustomStickerSendRepresentation representation,
  }) async => throw UnimplementedError('Custom sticker send preparation');

  Future<void> retire() async {}

  Future<void> drain() async {}
}
