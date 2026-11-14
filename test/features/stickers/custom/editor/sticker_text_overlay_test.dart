import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/features/stickers/custom/editor/sticker_still_export.dart';
import 'package:flutter_app/features/stickers/custom/editor/sticker_text_layers.dart';
import 'package:flutter_app/features/stickers/custom/editor/sticker_text_overlay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

List<int> _rgbaAt(Uint8List rgba, int x, int y) {
  final i = (y * 512 + x) * 4;
  return rgba.sublist(i, i + 4);
}

Uint8List _opaqueRedPng() {
  final image = img.Image(width: 64, height: 64, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(255, 0, 0, 255));
  return img.encodePng(image);
}

void main() {
  testWidgets('overlay is 512x512 straight RGBA, clear away from text', (
    tester,
  ) async {
    final rgba = (await tester.runAsync(
      () => rasterizeStickerTextOverlay(const [
        StickerTextLayer(id: 1, text: 'H'),
      ]),
    ))!;

    expect(rgba.length, 512 * 512 * 4);
    expect(_rgbaAt(rgba, 5, 5), [0, 0, 0, 0]);
    expect(_rgbaAt(rgba, 500, 40), [0, 0, 0, 0]);
    expect(_rgbaAt(rgba, 256, 256), [255, 255, 255, 255]);
  });

  testWidgets('overlay follows the layer position and colour', (tester) async {
    final rgba = (await tester.runAsync(
      () => rasterizeStickerTextOverlay(const [
        StickerTextLayer(
          id: 1,
          text: 'H',
          colour: StickerColourToken.red,
          center: Offset(0.25, 0.75),
        ),
      ]),
    ))!;

    expect(_rgbaAt(rgba, 128, 384), [255, 59, 48, 255]);
    expect(_rgbaAt(rgba, 256, 256), [0, 0, 0, 0]);
  });

  testWidgets('overlay of no layers is null', (tester) async {
    final rgba = await tester.runAsync(
      () => rasterizeStickerTextOverlay(const []),
    );

    expect(rgba, isNull);
  });

  testWidgets('circle export clears the corners but keeps the middle', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('stk2_export_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final output = File('${dir.path}/circle.png');

    final asset = (await tester.runAsync(
      () => exportStickerStill(
        sourceBytes: _opaqueRedPng(),
        layers: const [],
        shape: StickerShape.circle,
        outputFile: output,
      ),
    ))!;

    final bytes = output.readAsBytesSync();
    expect(asset.byteLength, bytes.length);
    expect(asset.sha256Hex, sha256.convert(bytes).toString());
    final png = img.decodePng(bytes)!;
    expect(png.getPixel(4, 4).a, 0);
    expect(png.getPixel(507, 507).a, 0);
    final middle = png.getPixel(256, 256);
    expect([middle.r, middle.g, middle.b, middle.a], [255, 0, 0, 255]);
  });
}
