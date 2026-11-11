import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/stickers/custom/create/sticker_create_screens.dart';
import 'package:flutter_app/features/stickers/domain/sticker_editor_result.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Future<void> _settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 250 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void main() {
  late Directory root;
  late File source;
  late Directory output;

  setUp(() {
    root = Directory.systemTemp.createTempSync('stk-recv-');
    source = File('${root.path}/received.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 40, height: 30)));
    output = Directory('${root.path}/lease')..createSync();
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<StickerEditorResult? Function()> open(WidgetTester tester) async {
    StickerEditorResult? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await editReceivedStickerPhoto(
              Navigator.of(context),
              sourceImagePath: source.path,
              outputDirectory: output,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final crop = find.widgetWithText(TextButton, 'Crop');
    await _settle(
      tester,
      () =>
          crop.evaluate().isNotEmpty &&
          tester.widget<TextButton>(crop).onPressed != null,
    );
    await tester.pumpAndSettle();
    return () => result;
  }

  testWidgets('crop then save writes the sticker inside the lease and keeps '
      'the source', (tester) async {
    final result = await open(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Crop'));
    await _settle(
      tester,
      () => find.text('Save sticker').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Crop'), findsNothing);
    await tester.tap(find.text('Save sticker'));
    await _settle(tester, () => result() != null);

    final asset = (result() as StickerEditorReady).asset;
    expect(File(asset.filePath).parent.path, output.path);
    expect(File(asset.filePath).existsSync(), isTrue);
    expect(source.existsSync(), isTrue);
  });

  testWidgets('backing out of crop cancels and writes nothing', (tester) async {
    final result = await open(tester);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(result(), isA<StickerEditorCancelled>());
    expect(output.listSync(), isEmpty);
    expect(source.existsSync(), isTrue);
  });
}
