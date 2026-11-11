import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/features/stickers/custom/editor/sticker_text_editor_screen.dart';
import 'package:flutter_app/features/stickers/domain/sticker_editor_result.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _halfTransparentRedPng() {
  final image = img.Image(width: 64, height: 64, numChannels: 4);
  for (var y = 0; y < 64; y++) {
    for (var x = 32; x < 64; x++) {
      image.setPixelRgba(x, y, 255, 0, 0, 255);
    }
  }
  return img.encodePng(image);
}

File _outputFile() {
  final dir = Directory.systemTemp.createTempSync('stk2_editor_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return File('${dir.path}/sticker.png');
}

Future<Future<StickerEditorResult?>> _openEditor(
  WidgetTester tester,
  File outputFile,
) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late Future<StickerEditorResult?> result;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () {
                result = Navigator.of(context).push<StickerEditorResult>(
                  MaterialPageRoute(
                    builder: (_) => StickerTextEditorScreen(
                      sourceBytes: _halfTransparentRedPng(),
                      outputFile: outputFile,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

Future<void> _addText(WidgetTester tester, String text) async {
  await tester.tap(find.byIcon(Icons.text_fields));
  await tester.pump();
  await tester.enterText(find.byType(TextField), text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

Rect _canvas(WidgetTester tester) =>
    tester.getRect(find.byKey(StickerTextEditorScreen.canvasKey));

double _width(WidgetTester tester, String text) =>
    (tester.getTopRight(find.text(text)) - tester.getTopLeft(find.text(text)))
        .distance;

double _angle(WidgetTester tester, String text) {
  final edge =
      tester.getTopRight(find.text(text)) - tester.getTopLeft(find.text(text));
  return math.atan2(edge.dy, edge.dx);
}

void main() {
  testWidgets('adding a layer shows its text at the canvas centre', (
    tester,
  ) async {
    await _openEditor(tester, _outputFile());

    await _addText(tester, 'Hello');

    expect(find.text('Hello'), findsOneWidget);
    expect(
      tester.getCenter(find.text('Hello')),
      offsetMoreOrLessEquals(_canvas(tester).center, epsilon: 0.5),
    );
  });

  testWidgets(
    'dragging moves the layer with the finger and stops at the edge',
    (tester) async {
      await _openEditor(tester, _outputFile());
      await _addText(tester, 'Hello');
      final finger = await tester.startGesture(
        tester.getCenter(find.text('Hello')),
      );
      await finger.moveBy(const Offset(30, 0));
      await tester.pump();
      final engaged = tester.getCenter(find.text('Hello'));

      await finger.moveBy(const Offset(40, -30));
      await tester.pump();
      expect(
        tester.getCenter(find.text('Hello')),
        offsetMoreOrLessEquals(engaged + const Offset(40, -30), epsilon: 0.5),
      );

      await finger.moveBy(const Offset(900, 0));
      await tester.pump();
      expect(
        tester.getCenter(find.text('Hello')).dx,
        moreOrLessEquals(_canvas(tester).right, epsilon: 0.5),
      );
      await finger.up();
    },
  );

  testWidgets('a pinch scales the layer with the finger span', (tester) async {
    await _openEditor(tester, _outputFile());
    await _addText(tester, 'Hello');
    final c = tester.getCenter(find.text('Hello'));
    final a = await tester.startGesture(c - const Offset(30, 0), pointer: 1);
    final b = await tester.startGesture(c + const Offset(30, 0), pointer: 2);
    Future<void> spreadTo(double half) async {
      await a.moveTo(c - Offset(half, 0));
      await b.moveTo(c + Offset(half, 0));
      await tester.pump();
    }

    for (final half in [40.0, 50.0]) {
      await spreadTo(half);
    }
    final engaged = _width(tester, 'Hello');
    for (final half in [70.0, 85.0, 100.0]) {
      await spreadTo(half);
    }

    expect(
      _width(tester, 'Hello') / engaged,
      moreOrLessEquals(2, epsilon: 0.02),
    );
    expect(_angle(tester, 'Hello'), moreOrLessEquals(0, epsilon: 0.01));
    await a.up();
    await b.up();
  });

  testWidgets('a two-finger turn rotates the layer by the same angle', (
    tester,
  ) async {
    await _openEditor(tester, _outputFile());
    await _addText(tester, 'Hello');
    final c = tester.getCenter(find.text('Hello'));
    final p = await tester.startGesture(c - const Offset(40, 0), pointer: 3);
    final q = await tester.startGesture(c + const Offset(40, 0), pointer: 4);
    Future<void> turnTo(int degrees) async {
      final angle = degrees * math.pi / 180;
      final arm = Offset(math.cos(angle) * 40, math.sin(angle) * 40);
      await p.moveTo(c - arm);
      await q.moveTo(c + arm);
      await tester.pump();
    }

    for (final degrees in [10, 20, 35, 50]) {
      await turnTo(degrees);
    }
    final engaged = _angle(tester, 'Hello');
    expect(engaged, greaterThan(0.1));
    for (final degrees in [65, 80, 90]) {
      await turnTo(degrees);
    }

    expect(
      _angle(tester, 'Hello') - engaged,
      moreOrLessEquals(40 * math.pi / 180, epsilon: 0.02),
    );
    await p.up();
    await q.up();
  });

  testWidgets('visible buttons move, resize and rotate the selected layer', (
    tester,
  ) async {
    await _openEditor(tester, _outputFile());
    await _addText(tester, 'Hello');
    final side = _canvas(tester).width;
    final start = tester.getCenter(find.text('Hello'));
    final width = _width(tester, 'Hello');

    await tester.tap(find.byTooltip('Move right'));
    await tester.tap(find.byTooltip('Move down'));
    await tester.pump();
    expect(
      tester.getCenter(find.text('Hello')),
      offsetMoreOrLessEquals(
        start + Offset(0.05 * side, 0.05 * side),
        epsilon: 0.5,
      ),
    );

    await tester.tap(find.byTooltip('Move left'));
    await tester.tap(find.byTooltip('Move up'));
    await tester.pump();
    expect(
      tester.getCenter(find.text('Hello')),
      offsetMoreOrLessEquals(start, epsilon: 0.5),
    );

    await tester.tap(find.byTooltip('Bigger'));
    await tester.pump();
    expect(
      _width(tester, 'Hello') / width,
      moreOrLessEquals(1.15, epsilon: 0.01),
    );
    await tester.tap(find.byTooltip('Smaller'));
    await tester.pump();
    expect(_width(tester, 'Hello') / width, moreOrLessEquals(1, epsilon: 0.01));

    await tester.tap(find.byTooltip('Rotate right'));
    await tester.pump();
    expect(
      _angle(tester, 'Hello'),
      moreOrLessEquals(math.pi / 12, epsilon: 0.01),
    );
    await tester.tap(find.byTooltip('Rotate left'));
    await tester.tap(find.byTooltip('Rotate left'));
    await tester.pump();
    expect(
      _angle(tester, 'Hello'),
      moreOrLessEquals(-math.pi / 12, epsilon: 0.01),
    );
  });

  testWidgets('delete removes the layer and undo brings it back', (
    tester,
  ) async {
    await _openEditor(tester, _outputFile());
    await _addText(tester, 'Hello');
    final start = tester.getCenter(find.text('Hello'));

    await tester.tap(find.byTooltip('Move right'));
    await tester.pump();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pump();
    expect(find.text('Hello'), findsNothing);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(find.text('Hello'), findsOneWidget);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(
      tester.getCenter(find.text('Hello')),
      offsetMoreOrLessEquals(start, epsilon: 0.5),
    );
  });

  testWidgets('after ten layers the Text button adds no eleventh', (
    tester,
  ) async {
    await _openEditor(tester, _outputFile());
    for (var i = 0; i < 10; i++) {
      await _addText(tester, 'L$i');
    }

    await tester.tap(find.byIcon(Icons.text_fields));
    await tester.pump();

    expect(find.byType(TextField), findsNothing);
    for (var i = 0; i < 10; i++) {
      expect(find.text('L$i'), findsOneWidget);
    }
  });

  testWidgets('an Arabic layer lays out right to left', (tester) async {
    await _openEditor(tester, _outputFile());
    await _addText(tester, 'مرحبا بك');
    await _addText(tester, 'Hello');

    RenderParagraph paragraph(String text) =>
        tester.renderObject<RenderParagraph>(find.text(text));
    expect(paragraph('مرحبا بك').textDirection, TextDirection.rtl);
    expect(paragraph('Hello').textDirection, TextDirection.ltr);
  });

  testWidgets('Save sticker returns a ready PNG matching its descriptor', (
    tester,
  ) async {
    final output = _outputFile();
    final result = await _openEditor(tester, output);
    await _addText(tester, 'H');

    await tester.tap(find.text('Save sticker'));
    StickerEditorResult? done;
    result.then((value) => done = value);
    for (var i = 0; i < 100 && done == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    final ready = done as StickerEditorReady;
    final asset = ready.asset;
    final bytes = output.readAsBytesSync();
    expect(asset.filePath, output.path);
    expect(asset.mime, 'image/png');
    expect(asset.frameCount, 1);
    expect(asset.durationMs, 0);
    expect(asset.byteLength, bytes.length);
    expect(asset.sha256Hex, sha256.convert(bytes).toString());
    expect(bytes.length, lessThanOrEqualTo(2097152));

    final png = img.decodePng(bytes)!;
    expect(
      [png.width, png.height, asset.width, asset.height],
      [512, 512, 512, 512],
    );
    final transparentSource = png.getPixel(32, 256);
    expect(transparentSource.a, 0);
    final redSource = png.getPixel(480, 256);
    expect(
      [redSource.r, redSource.g, redSource.b, redSource.a],
      [255, 0, 0, 255],
    );
    final glyph = png.getPixel(256, 256);
    expect([glyph.r, glyph.g, glyph.b, glyph.a], [255, 255, 255, 255]);
  });

  testWidgets('closing returns cancelled and writes no file', (tester) async {
    final output = _outputFile();
    final result = await _openEditor(tester, output);
    await _addText(tester, 'Hello');

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();

    expect(await result, isA<StickerEditorCancelled>());
    expect(output.existsSync(), isFalse);
  });

  testWidgets('a screen reader can pick a colour swatch', (tester) async {
    final semantics = tester.ensureSemantics();
    await _openEditor(tester, _outputFile());
    await _addText(tester, 'Hello');

    final node = tester.getSemantics(find.bySemanticsLabel('Red'));
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();

    final color = tester
        .renderObject<RenderParagraph>(find.text('Hello'))
        .text
        .style
        ?.color;
    expect(color?.toARGB32(), 0xFFFF3B30);
    semantics.dispose();
  });

  testWidgets('Cancel and back do nothing while the sticker is saving', (
    tester,
  ) async {
    final output = _outputFile();
    final result = await _openEditor(tester, output);
    await _addText(tester, 'H');

    StickerEditorResult? done;
    result.then((value) => done = value);
    await tester.tap(find.text('Save sticker'));
    await tester.pump();

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pump();
    expect(done, isNull);

    for (var i = 0; i < 100 && done == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(done, isA<StickerEditorReady>());
  });
}
