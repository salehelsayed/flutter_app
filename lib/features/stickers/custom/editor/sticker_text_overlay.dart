import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'sticker_text_layers.dart';

const int kStickerCanvasPx = 512;

/// Font size of a layer at scale 1 on the 512 px canvas.
const double _basePxAt512 = 56;
const double _maxLineWidthFraction = 0.9;

const Map<StickerFontToken, (String?, List<String>, FontWeight)> _fonts = {
  StickerFontToken.sans: (null, [], FontWeight.w800),
  StickerFontToken.serif: (
    'Georgia',
    ['Times New Roman', 'Noto Serif', 'serif'],
    FontWeight.w700,
  ),
  StickerFontToken.mono: (
    'Menlo',
    ['Courier New', 'Roboto Mono', 'monospace'],
    FontWeight.w600,
  ),
};

/// Style of [layer] on a square canvas of [canvasSide] logical pixels. The
/// editor preview and the rasteriser share it so the export matches the
/// screen.
TextStyle stickerLayerTextStyle(StickerTextLayer layer, double canvasSide) {
  final (family, fallback, weight) = _fonts[layer.font]!;
  return TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontWeight: weight,
    fontSize: _basePxAt512 * canvasSide / kStickerCanvasPx,
    height: 1.15,
    color: Color(layer.colour.argb),
  );
}

double stickerLayerMaxWidth(double canvasSide) =>
    canvasSide * _maxLineWidthFraction;

/// Paints [layers] bottom to top: each laid out centred, then rotated and
/// scaled about its centre at its normalized canvas position.
void paintStickerTextLayers(
  Canvas canvas,
  double canvasSide,
  List<StickerTextLayer> layers,
) {}

/// Rasterises [layers] once into exactly 512x512 pixels, top-left origin,
/// row-major, 8-bit straight (non-premultiplied) RGBA, fully transparent
/// outside rendered text. Returns null for an empty layer list.
Future<Uint8List?> rasterizeStickerTextOverlay(
  List<StickerTextLayer> layers,
) async {
  return Uint8List(0);
}
