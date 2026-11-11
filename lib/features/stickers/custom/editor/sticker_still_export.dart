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
  const side = kStickerCanvasPx;
  final codec = await ui.instantiateImageCodec(sourceBytes);
  final source = (await codec.getNextFrame()).image;
  codec.dispose();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const bounds = Rect.fromLTWH(0, 0, side + 0.0, side + 0.0);
  canvas.saveLayer(bounds, Paint());
  paintImage(
    canvas: canvas,
    rect: bounds,
    image: source,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
  );
  paintStickerTextLayers(canvas, side.toDouble(), layers);
  if (shape == StickerShape.circle) {
    canvas
      ..saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn)
      ..drawOval(bounds, Paint())
      ..restore();
  }
  canvas.restore();
  source.dispose();

  final picture = recorder.endRecording();
  final image = await picture.toImage(side, side);
  picture.dispose();
  final ByteData? png;
  try {
    png = await image.toByteData(format: ui.ImageByteFormat.png);
  } finally {
    image.dispose();
  }
  final bytes = png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  if (bytes.length > kStickerEditorMaxPngBytes) {
    throw StateError('sticker PNG ${bytes.length} bytes exceeds 2 MiB');
  }
  await outputFile.writeAsBytes(bytes, flush: true);
  return NormalizedStickerAsset(
    filePath: outputFile.path,
    sha256Hex: sha256.convert(bytes).toString(),
    mime: 'image/png',
    byteLength: bytes.length,
    width: side,
    height: side,
    frameCount: 1,
    durationMs: 0,
  );
}
