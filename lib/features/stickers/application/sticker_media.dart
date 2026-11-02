import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/features/stickers/domain/sticker_catalog.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const int kStickerPixelSize = 512;

/// Copies a bundled sticker to the temporary directory, where the image
/// picker leaves picked photos, so it enters the ordinary image send path as
/// is: no resizing and no recompression.
Future<PendingComposerMedia> prepareStickerMedia(
  StickerEntry sticker, {
  AssetBundle? bundle,
}) async {
  final data = await (bundle ?? rootBundle).load(sticker.assetPath);
  final directory = await getTemporaryDirectory();
  final file = File(
    p.join(
      directory.path,
      'sticker_${DateTime.now().microsecondsSinceEpoch}'
      '${p.extension(sticker.assetPath)}',
    ),
  );
  await file.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
  return PendingComposerMedia(
    file: file,
    budgetBytes: data.lengthInBytes,
    width: kStickerPixelSize,
    height: kStickerPixelSize,
  );
}

StickerCatalog? _bundledCatalog;

/// The bundled catalog, parsed once per process.
Future<StickerCatalog> loadBundledStickerCatalog() async =>
    _bundledCatalog ??= StickerCatalog.parse(
      await rootBundle.loadString(kStickerPacksAssetPath),
      includeTestOnly: kIncludeTestOnlyStickers,
    );
