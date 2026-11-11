import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/features/stickers/custom/create/sticker_create_flow.dart';
import 'package:flutter_app/features/stickers/custom/create/sticker_create_screens.dart';
import 'package:flutter_app/features/stickers/custom/editor/sticker_still_export.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../fake_custom_sticker_library.dart';

Widget _app(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

class _OnePhotoPicker implements MediaPicker {
  _OnePhotoPicker(this.path);

  final String path;

  @override
  Future<XFile?> pickImage({required ImageSource source}) async => XFile(path);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settleUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 250 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void main() {
  group('centeredSquareCrop', () {
    test('a portrait frame keeps the full width, centred vertically', () {
      expect(
        centeredSquareCrop(const Size(1080, 1920)),
        const Rect.fromLTRB(0, 0.21875, 1, 0.78125),
      );
    });

    test('a landscape frame keeps the full height, centred horizontally', () {
      expect(
        centeredSquareCrop(const Size(2000, 1000)),
        const Rect.fromLTRB(0.25, 0, 0.75, 1),
      );
    });
  });

  group('deleteStickerTemp', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('stk-del-'));
    tearDown(() => root.deleteSync(recursive: true));

    test('deletes a plain file and keeps its folder', () async {
      final file = File('${root.path}/photo.jpg')..writeAsBytesSync([1]);

      await deleteStickerTemp(file.path);

      expect(file.existsSync(), isFalse);
      expect(root.existsSync(), isTrue);
    });

    test('deletes a clip export job folder with its poster', () async {
      final job = Directory('${root.path}/mknoon-sticker-animation-abc')
        ..createSync();
      final webp = File('${job.path}/sticker.webp')..writeAsBytesSync([1]);
      File('${job.path}/poster.png').writeAsBytesSync([2]);

      await deleteStickerTemp(webp.path);

      expect(job.existsSync(), isFalse);
    });

    test('a missing file is not an error', () async {
      await deleteStickerTemp('${root.path}/gone.png');
    });
  });

  testWidgets('the source sheet offers photo, gallery and clip', (
    tester,
  ) async {
    StickerCreateSource? picked;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                picked = await showStickerCreateSourceSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('New sticker'), findsOneWidget);
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
    await tester.tap(find.text('Record clip'));
    await tester.pumpAndSettle();

    expect(picked, StickerCreateSource.cameraClip);
  });

  testWidgets('the source sheet reads right to left in Arabic', (tester) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showStickerCreateSourceSheet(context),
            child: const Text('open'),
          ),
        ),
        locale: const Locale('ar'),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('ملصق جديد'), findsOneWidget);
    final clip = find.text('تسجيل مقطع');
    expect(Directionality.of(tester.element(clip)), TextDirection.rtl);
    final photo = find.text('التقاط صورة');
    expect(
      tester.getCenter(find.byIcon(Icons.photo_camera_outlined)).dx,
      greaterThan(tester.getCenter(photo).dx),
    );
  });

  testWidgets('the crop screen returns the cropped square and chosen shape', (
    tester,
  ) async {
    final png = img.encodePng(img.Image(width: 40, height: 30));
    StickerStillCrop? result;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await Navigator.of(context).push<StickerStillCrop>(
                  MaterialPageRoute(
                    builder: (_) => StickerCropScreen(imageBytes: png),
                  ),
                ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final crop = find.widgetWithText(TextButton, 'Crop');
    expect(tester.widget<TextButton>(crop).onPressed, isNull);
    for (var i = 0; i < 50; i++) {
      if (tester.widget<TextButton>(crop).onPressed != null) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }

    await tester.tap(find.text('Circle'));
    await tester.pump();
    await tester.tap(find.text('Crop'));
    for (var i = 0; i < 20 && result == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(result?.shape, StickerShape.circle);
    final cropped = img.decodePng(result!.bytes)!;
    expect(cropped.width, cropped.height);
  });

  testWidgets('a gallery photo is copied first, so backing out of crop keeps '
      'the original and cleans the copy', (tester) async {
    final root = Directory.systemTemp.createTempSync('stk-pick-');
    addTearDown(() => root.deleteSync(recursive: true));
    final original = File('${root.path}/IMG_0001.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 40, height: 30)));
    final temp = Directory('${root.path}/tmp')..createSync();
    Future<void>? running;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => running = openStickerCreate(
                context,
                library: FakeCustomStickerLibrary(),
                picker: _OnePhotoPicker(original.path),
                temporaryDirectory: () async => temp,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gallery'));
    final crop = find.widgetWithText(TextButton, 'Crop');
    await _settleUntil(
      tester,
      () =>
          crop.evaluate().isNotEmpty &&
          tester.widget<TextButton>(crop).onPressed != null,
    );
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    var finished = false;
    unawaited(running!.whenComplete(() => finished = true));
    await _settleUntil(tester, () => finished);
    expect(finished, isTrue);

    expect(original.existsSync(), isTrue);
    expect(temp.listSync(), isEmpty);
  });

  group('stickerCreateMessage', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final saved = StickerCreateSaved(
      CustomSticker(
        id: 'a',
        asset: fakeStickerAsset('a'),
        createdAtMs: 0,
        lastUsedAtMs: 0,
        position: 0,
      ),
    );

    test('saved, full, failed and cancelled read as approved', () {
      expect(stickerCreateMessage(l10n, saved), 'Saved to My stickers');
      for (final code in [
        CustomStickerErrorCode.countQuota,
        CustomStickerErrorCode.byteQuota,
      ]) {
        expect(
          stickerCreateMessage(l10n, StickerCreateFailed(code)),
          'My stickers is full. Delete one to add another.',
        );
      }
      expect(
        stickerCreateMessage(
          l10n,
          const StickerCreateFailed(CustomStickerErrorCode.storageFailure),
        ),
        "Couldn't save this sticker. Try again.",
      );
      expect(
        stickerCreateMessage(l10n, const StickerCreateCancelled()),
        isNull,
      );
    });

    test('Arabic messages are the approved copy', () {
      final ar = lookupAppLocalizations(const Locale('ar'));
      expect(stickerCreateMessage(ar, saved), 'تم الحفظ في ملصقاتي');
      expect(
        stickerCreateMessage(
          ar,
          const StickerCreateFailed(CustomStickerErrorCode.byteQuota),
        ),
        'ملصقاتي ممتلئة. احذف ملصقًا لإضافة آخر.',
      );
    });

    test('German quotes the library name', () {
      expect(
        stickerCreateMessage(
          lookupAppLocalizations(const Locale('de')),
          const StickerCreateFailed(CustomStickerErrorCode.countQuota),
        ),
        '„Meine Sticker“ ist voll. Lösche einen, um einen neuen hinzuzufügen.',
      );
    });
  });
}
