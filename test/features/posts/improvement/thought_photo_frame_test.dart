import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/posts/application/post_media_draft.dart';
import 'package:flutter_app/features/posts/presentation/thought_photo_framing.dart';
import 'package:flutter_app/features/posts/presentation/widgets/compose_post_sheet.dart';
import 'package:flutter_app/features/posts/presentation/widgets/thought_photo_draft_preview.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('frame131_widget_'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// Red, green, blue and yellow quarters, top left to bottom right.
  String quarters(String name, int width, int height) {
    final image = img.Image(width: width, height: height);
    for (final pixel in image) {
      final right = pixel.x >= width / 2;
      final bottom = pixel.y >= height / 2;
      pixel
        ..r = right == bottom ? 255 : 0
        ..g = right ? 255 : 0
        ..b = !right && bottom ? 255 : 0;
    }
    final path = '${dir.path}/$name.jpg';
    File(path).writeAsBytesSync(img.encodeJpg(image, quality: 95));
    return path;
  }

  String colour(img.Image image, int x, int y) {
    final p = image.getPixel(x, y);
    final on = [p.r, p.g, p.b].map((c) => c > 160).toList();
    return switch (on) {
      [true, false, false] => 'red',
      [false, true, false] => 'green',
      [false, false, true] => 'blue',
      [true, true, false] => 'yellow',
      _ => 'rgb(${p.r},${p.g},${p.b})',
    };
  }

  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 300 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(done(), isTrue);
  }

  final frame = find.byKey(const ValueKey('thought-photo-frame'));
  final framedImage = find.byKey(const ValueKey('thought-photo-framed-image'));

  Future<void> openWith(
    WidgetTester tester,
    List<String> paths, {
    Locale locale = const Locale('en'),
    List<ComposePostResult>? submitted,
  }) async {
    tester.view.physicalSize = const Size(400, 900) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ComposePostSheet(
            thoughtsOnly: true,
            eligibleContacts: const [],
            onPickMedia: () async => (
              drafts: [
                for (final path in paths)
                  PostMediaDraft(localFilePath: path, mime: 'image/jpeg'),
              ],
              leftOut: false,
            ),
            onSubmitWithOutcome: (result) async {
              submitted?.add(result);
              return ComposePostSubmitOutcome.keepSheetOpen;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('thought-composer-media')));
    await tester.pump();
    await until(tester, () => framedImage.evaluate().isNotEmpty);
  }

  Map<String, PhotoFraming> framings(WidgetTester tester) => tester
      .widget<ThoughtPhotoDraftPreview>(find.byType(ThoughtPhotoDraftPreview))
      .framings;

  Future<void> drag(WidgetTester tester, Offset by) async {
    await tester.drag(frame, by);
    await tester.pump();
  }

  Future<void> showPhoto(WidgetTester tester, int index) async {
    await tester.tap(find.byKey(ValueKey('thought-photo-thumb-$index')));
    await tester.pump();
    await until(tester, () => framedImage.evaluate().isNotEmpty);
  }

  Future<List<img.Image>> share(
    WidgetTester tester,
    List<ComposePostResult> submitted,
  ) async {
    await tester.tap(find.byKey(const ValueKey('thought-composer-share')));
    await until(tester, () => submitted.isNotEmpty);
    return [
      for (final draft in submitted.single.mediaDrafts)
        img.decodeJpg(File(draft.localFilePath).readAsBytesSync())!,
    ];
  }

  testWidgets('a picked photo shows covering a square frame with the grid '
      'and the hint', (tester) async {
    final photo = quarters('lake', 400, 300);
    await openWith(tester, [photo]);

    final box = tester.getRect(frame);
    expect(box.width, 360);
    expect(box.height, 360);
    expect(
      find.text('Pinch and drag to choose what friends see'),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString() == '_ThirdsPainter',
      ),
      findsOneWidget,
    );
    expect(
      tester.getRect(framedImage),
      Rect.fromLTWH(box.left - 60, box.top, 480, 360),
    );
    expect(
      framings(tester)[photo]!.cropRect(const Size(400, 300)),
      const Rect.fromLTWH(50, 0, 300, 300),
    );
  });

  testWidgets('a drag and a pinch change the framing, never leaving an '
      'empty edge', (tester) async {
    final photo = quarters('dusk', 400, 300);
    await openWith(tester, [photo]);
    final box = tester.getRect(frame);

    await drag(tester, const Offset(500, -400));
    expect(
      framings(tester)[photo]!.cropRect(const Size(400, 300)),
      const Rect.fromLTWH(0, 0, 300, 300),
    );
    expect(
      tester.getRect(framedImage),
      Rect.fromLTWH(box.left, box.top, 480, 360),
    );

    final centre = box.center;
    final a = await tester.startGesture(centre - const Offset(20, 0));
    final b = await tester.startGesture(centre + const Offset(20, 0));
    for (var step = 1; step <= 10; step++) {
      await a.moveTo(centre - Offset(20.0 + step * 12, 0));
      await b.moveTo(centre + Offset(20.0 + step * 12, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pump();
    expect(framings(tester)[photo]!.scale, inInclusiveRange(2, 4));

    await drag(tester, const Offset(-2000, -2000));
    final shown = tester.getRect(framedImage);
    expect(shown.right, moreOrLessEquals(box.right, epsilon: .01));
    expect(shown.bottom, moreOrLessEquals(box.bottom, epsilon: .01));
    expect(shown.left, lessThan(box.left));
    expect(shown.top, lessThan(box.top));
  });

  testWidgets('sharing sends the baked square of the framing as the photo', (
    tester,
  ) async {
    final photo = quarters('square', 400, 300);
    final submitted = <ComposePostResult>[];
    await openWith(tester, [photo], submitted: submitted);
    await drag(tester, const Offset(500, 0));

    final [out] = await share(tester, submitted);
    final draft = submitted.single.mediaDrafts.single;
    expect(draft.localFilePath, isNot(photo));
    expect(draft.mime, 'image/jpeg');
    expect([out.width, out.height], [300, 300]);
    expect(
      [colour(out, 8, 8), colour(out, 190, 8), colour(out, 210, 8)],
      ['red', 'red', 'green'],
    );
  });

  testWidgets('each photo keeps its own framing and is baked from it', (
    tester,
  ) async {
    final wide = quarters('wide', 400, 300);
    final tall = quarters('tall', 300, 400);
    final submitted = <ComposePostResult>[];
    await openWith(tester, [wide, tall], submitted: submitted);

    await drag(tester, const Offset(500, 0));
    await showPhoto(tester, 1);
    expect(
      framings(tester)[tall]!.cropRect(const Size(300, 400)),
      const Rect.fromLTWH(0, 50, 300, 300),
    );
    await drag(tester, const Offset(0, 500));
    await showPhoto(tester, 0);
    expect(
      tester.getRect(framedImage).left,
      moreOrLessEquals(tester.getRect(frame).left, epsilon: .01),
    );
    expect(
      framings(tester)[wide]!.cropRect(const Size(400, 300)),
      const Rect.fromLTWH(0, 0, 300, 300),
    );
    expect(
      framings(tester)[tall]!.cropRect(const Size(300, 400)),
      const Rect.fromLTWH(0, 0, 300, 300),
    );

    final [wideOut, tallOut] = await share(tester, submitted);
    expect([wideOut.width, tallOut.width], [300, 300]);
    expect(
      [colour(wideOut, 190, 8), colour(wideOut, 210, 8)],
      ['red', 'green'],
    );
    expect([colour(tallOut, 8, 190), colour(tallOut, 8, 210)], ['red', 'blue']);
  });

  testWidgets('removing one photo keeps the other photo and its framing', (
    tester,
  ) async {
    final wide = quarters('first', 400, 300);
    final tall = quarters('second', 300, 400);
    await openWith(tester, [wide, tall]);
    await showPhoto(tester, 1);
    await drag(tester, const Offset(0, 500));
    await showPhoto(tester, 0);

    await tester.tap(find.byKey(const ValueKey('thought-photo-draft-remove')));
    await tester.pump();
    await until(tester, () => framedImage.evaluate().isNotEmpty);

    final preview = tester.widget<ThoughtPhotoDraftPreview>(
      find.byType(ThoughtPhotoDraftPreview),
    );
    expect(preview.paths, [tall]);
    expect(
      preview.framings[tall]!.cropRect(const Size(300, 400)),
      const Rect.fromLTWH(0, 0, 300, 300),
    );
    expect(
      tester.getRect(framedImage).top,
      moreOrLessEquals(tester.getRect(frame).top, epsilon: .01),
    );
  });

  for (final (locale, hint) in const [
    (Locale('de'), 'Zoomen und verschieben: Wähle, was Freunde sehen'),
    (Locale('ar'), 'قرّب واسحب لتختار ما يراه أصدقاؤك'),
  ]) {
    testWidgets('${locale.languageCode} shows its hint centred in the frame', (
      tester,
    ) async {
      await openWith(tester, [
        quarters('hint_${locale.languageCode}', 400, 300),
      ], locale: locale);
      expect(find.text(hint), findsOneWidget);
      expect(
        tester
            .getCenter(find.byKey(const ValueKey('thought-photo-frame-hint')))
            .dx,
        moreOrLessEquals(tester.getCenter(frame).dx, epsilon: .5),
      );
    });
  }
}
