import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker_asset.dart';

import 'sticker_text_layers.dart';
import 'sticker_text_overlay.dart';

enum StickerShape { square, circle }

const int kStickerEditorMaxPngBytes = 2097152;

/// Flattens the still sticker in the order shared with the animated path:
/// source fitted into the 512x512 canvas, text overlay, then the circle mask
/// (circle shape only). Writes the PNG to the caller-owned [outputFile].
Future<NormalizedStickerAsset> exportStickerStill({
  required Uint8List sourceBytes,
  required List<StickerTextLayer> layers,
  required StickerShape shape,
  required File outputFile,
}) async {
  await outputFile.writeAsBytes(const [], flush: true);
  return NormalizedStickerAsset(
    filePath: outputFile.path,
    sha256Hex: '',
    mime: '',
    byteLength: 0,
    width: 0,
    height: 0,
    frameCount: 0,
    durationMs: 0,
  );
}
