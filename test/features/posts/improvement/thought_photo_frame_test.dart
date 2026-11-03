import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/posts/application/post_media_draft.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
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

  /// [quarters] inside a 24-pixel frame of rgb(40, 120, 200).
  String bordered(String name, int width, int height) {
    final image = img.Image(width: width, height: height);
    for (final pixel in image) {
      final edge =
          pixel.x < 24 ||
          pixel.y < 24 ||
          pixel.x >= width - 24 ||
          pixel.y >= height - 24;
      final right = pixel.x >= width / 2;
      final bottom = pixel.y >= height / 2;
      pixel
        ..r = edge ? 40 : (right == bottom ? 255 : 0)
        ..g = edge ? 120 : (right ? 255 : 0)
        ..b = edge ? 200 : (!right && bottom ? 255 : 0);
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
    bool restored = false,
  }) async {
    final drafts = [
      for (final path in paths)
        PostMediaDraft(localFilePath: path, mime: 'image/jpeg'),
    ];
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
            initialDraft: restored
                ? ComposePostResult(
                    text: '',
                    audience: PostAudience.allFriends(),
                    mediaDrafts: drafts,
                  )
                : null,
            onPickMedia: () async => (drafts: drafts, leftOut: false),
            onSubmitWithOutcome: (result) async {
              submitted?.add(result);
              return ComposePostSubmitOutcome.keepSheetOpen;
            },
          ),
        ),
      ),
    );
    if (!restored) {
      await tester.tap(find.byKey(const ValueKey('thought-composer-media')));
      await tester.pump();
    }
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
    expect(framings(tester)[photo]!.scale, 1, reason: 'cover by default');
  });

  testWidgets('a pinch out shows the whole wide photo on its edge colour, '
      'and Share bakes the same picture', (tester) async {
    final photo = bordered('wide_out', 400, 300);
    final submitted = <ComposePostResult>[];
    await openWith(tester, [photo], submitted: submitted);
    final box = tester.getRect(frame);
    final fill = find.byKey(const ValueKey('thought-photo-frame-fill'));
    await until(tester, () => fill.evaluate().isNotEmpty);

    final centre = box.center;
    final a = await tester.startGesture(centre - const Offset(120, 0));
    final b = await tester.startGesture(centre + const Offset(120, 0));
    for (var step = 1; step <= 10; step++) {
      await a.moveTo(centre - Offset(120.0 - step * 10, 0));
      await b.moveTo(centre + Offset(120.0 - step * 10, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pump();

    expect(framings(tester)[photo]!.scale, .75);
    final shown = tester.getRect(framedImage);
    expect(shown.left, moreOrLessEquals(box.left, epsilon: .01));
    expect(shown.right, moreOrLessEquals(box.right, epsilon: .01));
    expect(shown.top, moreOrLessEquals(box.top + 45, epsilon: .01));
    expect(shown.bottom, moreOrLessEquals(box.bottom - 45, epsilon: .01));
    await drag(tester, const Offset(0, 300));
    expect(
      tester.getRect(framedImage).top,
      moreOrLessEquals(box.top + 45, epsilon: .01),
      reason: 'the whole photo stays centred',
    );

    final preview = tester.widget<ColoredBox>(fill).color;
    final [out] = await share(tester, submitted);
    expect([out.width, out.height], [400, 400]);
    for (final (x, y) in const [(8, 8), (200, 30), (391, 391), (200, 370)]) {
      final p = out.getPixel(x, y);
      expect(
        [p.r, p.g, p.b],
        [
          closeTo((preview.r * 255).round(), 10),
          closeTo((preview.g * 255).round(), 10),
          closeTo((preview.b * 255).round(), 10),
        ],
        reason: 'band pixel $x,$y matches the preview fill',
      );
    }
    expect([colour(out, 40, 90), colour(out, 359, 309)], ['red', 'yellow']);
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

  testWidgets('a photo never shown in the frame is shared as a square too', (
    tester,
  ) async {
    final wide = quarters('shown', 400, 300);
    final tall = quarters('never_shown', 300, 400);
    final submitted = <ComposePostResult>[];
    await openWith(tester, [wide, tall], submitted: submitted);

    final [wideOut, tallOut] = await share(tester, submitted);
    expect(
      [
        [wideOut.width, wideOut.height],
        [tallOut.width, tallOut.height],
      ],
      [
        [300, 300],
        [300, 300],
      ],
    );
    expect([colour(tallOut, 8, 140), colour(tallOut, 8, 160)], ['red', 'blue']);
  });

  testWidgets('a bake that cannot be written shares nothing, keeps the '
      'draft and its framing, and a retry shares the framed square', (
    tester,
  ) async {
    final path = quarters('private_crop', 400, 300);
    final original = File(path);
    final submitted = <ComposePostResult>[];
    await openWith(tester, [path], submitted: submitted);
    await drag(tester, const Offset(500, 0));
    final framing = framings(tester)[path]!;

    await IOOverrides.runZoned(() async {
      await tester.tap(find.byKey(const ValueKey('thought-composer-share')));
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
    }, createFile: (name) => name == path ? original : _NoSpaceFile(name));

    expect(submitted, isEmpty, reason: 'never the uncropped original');
    expect(
      find.text('Not shared yet. Your thought is still here.'),
      findsOneWidget,
    );
    expect(framedImage, findsOneWidget);
    expect(framings(tester)[path]!.center, framing.center);

    final [out] = await share(tester, submitted);
    expect([out.width, out.height], [300, 300]);
    expect([colour(out, 190, 8), colour(out, 210, 8)], ['red', 'green']);
  });

  testWidgets('closing and reopening a draft keeps each photo\'s framing', (
    tester,
  ) async {
    final wide = quarters('restore_wide', 400, 300);
    final tall = quarters('restore_tall', 300, 400);
    ComposePostResult? saved;
    Future<void> mount({ComposePostResult? initial}) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ComposePostSheet(
              thoughtsOnly: true,
              eligibleContacts: const [],
              initialDraft: initial,
              onPickMedia: () async => (
                drafts: [
                  for (final path in [wide, tall])
                    PostMediaDraft(localFilePath: path, mime: 'image/jpeg'),
                ],
                leftOut: false,
              ),
              onSubmit: (_) async {},
              onClosed: (value) => saved = value,
            ),
          ),
        ),
      );
    }

    tester.view.physicalSize = const Size(400, 900) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await mount();
    await tester.tap(find.byKey(const ValueKey('thought-composer-media')));
    await tester.pump();
    await until(tester, () => framedImage.evaluate().isNotEmpty);
    await drag(tester, const Offset(90, 0));
    final before = framings(tester);
    expect(before[wide]!.center, isNot(const Offset(.5, .5)));

    await tester.pumpWidget(const SizedBox.shrink());
    expect(saved, isNotNull);
    await mount(initial: saved);
    await until(tester, () => framedImage.evaluate().isNotEmpty);

    final after = framings(tester);
    expect(after[wide]!.center, before[wide]!.center);
    expect(after[wide]!.scale, before[wide]!.scale);
    expect(after[tall]!.center, const Offset(.5, .5));
    expect(after[tall]!.scale, 1);
  });

  for (final (width, height) in const [(5000, 1), (5000, 3), (1, 5000)]) {
    testWidgets('a ${width}x$height strip opens in the frame and zooms out to '
        'the whole strip', (tester) async {
      final source = img.Image(width: width, height: height);
      img.fill(source, color: img.ColorRgb8(200, 80, 20));
      final path = '${dir.path}/strip_${width}x$height.png';
      File(path).writeAsBytesSync(img.encodePng(source));
      await openWith(tester, [path]);
      final rect = tester.getRect(framedImage);
      final fitted = PhotoFraming.cover.pinched(
        Size(rect.width, rect.height),
        360,
        from: const Offset(100, 100),
        to: const Offset(100, 100),
        zoom: .000001,
      );
      expect(
        fitted.cropRect(Size(width.toDouble(), height.toDouble())).width,
        closeTo(5000, .01),
      );
    });
  }

  testWidgets('a photo that failed to open opens once the same file is '
      'readable again', (tester) async {
    final path = '${dir.path}/recovering.jpg';
    File(path).writeAsBytesSync([1, 2, 3, 4]);
    final drafts = [PostMediaDraft(localFilePath: path, mime: 'image/jpeg')];
    tester.view.physicalSize = const Size(400, 900) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ComposePostSheet(
            thoughtsOnly: true,
            eligibleContacts: const [],
            onPickMedia: () async => (drafts: drafts, leftOut: false),
            onSubmit: (_) async {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('thought-composer-media')));
    await tester.pump();
    await until(
      tester,
      () => find.byIcon(Icons.broken_image_outlined).evaluate().isNotEmpty,
    );
    await tester.pumpWidget(const SizedBox());

    File(
      path,
    ).writeAsBytesSync(File(quarters('valid', 400, 300)).readAsBytesSync());
    await openWith(tester, [path]);
    expect(framedImage, findsOneWidget);
  });

  final fit = find.byKey(const ValueKey('thought-photo-fit'));
  final fill = find.byKey(const ValueKey('thought-photo-fill'));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('Fit shows the whole photo on its edge colour and Share bakes '
      'it whole', (tester) async {
    final photo = bordered('fit_wide', 400, 300);
    final submitted = <ComposePostResult>[];
    await openWith(tester, [photo], submitted: submitted);
    final box = tester.getRect(frame);
    expect(find.text('Fit'), findsOneWidget);
    expect(find.text('Fill'), findsOneWidget);

    await tester.tap(fit);
    await settle(tester);
    expect(framings(tester)[photo]!.scale, .75);
    final shown = tester.getRect(framedImage);
    expect(shown.left, moreOrLessEquals(box.left, epsilon: .01));
    expect(shown.right, moreOrLessEquals(box.right, epsilon: .01));
    expect(shown.top, moreOrLessEquals(box.top + 45, epsilon: .01));

    final [out] = await share(tester, submitted);
    expect([out.width, out.height], [400, 400]);
    expect([colour(out, 40, 90), colour(out, 359, 309)], ['red', 'yellow']);
  });

  testWidgets('Fill brings back the centred cover after Fit or a drag', (
    tester,
  ) async {
    final photo = quarters('fill_wide', 400, 300);
    await openWith(tester, [photo]);
    final box = tester.getRect(frame);
    await tester.tap(fit);
    await settle(tester);
    await tester.tap(fill);
    await settle(tester);
    expect(framings(tester)[photo]!.scale, 1);
    expect(framings(tester)[photo]!.center, const Offset(.5, .5));
    await drag(tester, const Offset(500, 0));
    await tester.tap(fill);
    await settle(tester);
    expect(framings(tester)[photo]!.center, const Offset(.5, .5));
    expect(
      tester.getRect(framedImage),
      Rect.fromLTWH(box.left - 60, box.top, 480, 360),
    );
  });

  testWidgets('a drag during the Fit glide carries on from where the photo '
      'is shown', (tester) async {
    final photo = quarters('glide', 400, 300);
    await openWith(tester, [photo]);
    await tester.tap(fit);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final mid = tester.getRect(framedImage);
    expect(mid.width, inExclusiveRange(361, 479), reason: 'mid-glide');

    final finger = await tester.startGesture(tester.getRect(frame).center);
    await tester.pump();
    await finger.moveBy(const Offset(2, 0));
    await tester.pump();
    final moved = tester.getRect(framedImage);
    expect(moved.width, moreOrLessEquals(mid.width, epsilon: .5));
    expect(moved.left, moreOrLessEquals(mid.left + 2, epsilon: 1));
    await finger.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.getRect(framedImage).width,
      moreOrLessEquals(mid.width, epsilon: .5),
      reason: 'the glide does not resume',
    );
  });

  testWidgets('with reduce motion Fit jumps to the whole photo at once', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final photo = quarters('fit_still', 400, 300);
    await openWith(tester, [photo]);
    final box = tester.getRect(frame);
    await tester.tap(fit);
    await tester.pump();
    expect(
      tester.getRect(framedImage).top,
      moreOrLessEquals(box.top + 45, epsilon: .01),
    );
  });

  testWidgets('Fit and Fill say which is chosen, and neither once the photo '
      'is pinched', (tester) async {
    final handle = tester.ensureSemantics();
    final photo = quarters('chosen', 400, 300);
    await openWith(tester, [photo]);
    Matcher chosen(String label, bool selected) => isSemantics(
      label: label,
      isButton: true,
      hasSelectedState: true,
      isSelected: selected,
      hasTapAction: true,
    );
    expect(tester.getSemantics(fit), chosen('Fit', false));
    expect(tester.getSemantics(fill), chosen('Fill', true));
    await tester.tap(fit);
    await settle(tester);
    expect(tester.getSemantics(fit), chosen('Fit', true));
    expect(tester.getSemantics(fill), chosen('Fill', false));

    final centre = tester.getRect(frame).center;
    final a = await tester.startGesture(centre - const Offset(20, 0));
    final b = await tester.startGesture(centre + const Offset(20, 0));
    for (var step = 1; step <= 10; step++) {
      await a.moveTo(centre - Offset(20.0 + step * 6, 0));
      await b.moveTo(centre + Offset(20.0 + step * 6, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pump();
    expect(tester.getSemantics(fit), chosen('Fit', false));
    expect(tester.getSemantics(fill), chosen('Fill', false));
    handle.dispose();
  });

  testWidgets('Fit and Fill are at least 44 pt tall, sit under the frame, and '
      'swap sides right to left', (tester) async {
    await openWith(tester, [quarters('ltr', 400, 300)]);
    final box = tester.getRect(frame);
    for (final control in [fit, fill]) {
      final rect = tester.getRect(control);
      expect(rect.height, greaterThanOrEqualTo(44));
      expect(rect.top, greaterThanOrEqualTo(box.bottom));
    }
    expect(tester.getCenter(fit).dx, lessThan(tester.getCenter(fill).dx));

    await tester.pumpWidget(const SizedBox());
    await openWith(tester, [
      quarters('rtl', 400, 300),
    ], locale: const Locale('ar'));
    expect(tester.getCenter(fit).dx, greaterThan(tester.getCenter(fill).dx));
  });

  testWidgets('a square photo has no Fit or Fill, there is nothing to choose', (
    tester,
  ) async {
    await openWith(tester, [quarters('square_photo', 300, 300)]);
    expect(fit, findsNothing);
    expect(fill, findsNothing);
  });

  testWidgets('each thumbnail reads as Photo n of count, the shown one '
      'selected', (tester) async {
    final handle = tester.ensureSemantics();
    await openWith(tester, [
      quarters('thumb_a', 400, 300),
      quarters('thumb_b', 300, 400),
    ]);
    Matcher thumb(String label, bool selected) => isSemantics(
      label: label,
      isButton: true,
      hasSelectedState: true,
      isSelected: selected,
      hasTapAction: true,
    );
    final first = find.byKey(const ValueKey('thought-photo-thumb-0'));
    final second = find.byKey(const ValueKey('thought-photo-thumb-1'));
    expect(tester.getSemantics(first), thumb('Photo 1 of 2', true));
    expect(tester.getSemantics(second), thumb('Photo 2 of 2', false));
    await showPhoto(tester, 1);
    expect(tester.getSemantics(first), thumb('Photo 1 of 2', false));
    expect(tester.getSemantics(second), thumb('Photo 2 of 2', true));
    expect(
      find.descendant(
        of: find.byType(ThoughtPhotoDraftPreview),
        matching: find.bySemanticsLabel(
          RegExp(r'\.jpg|image', caseSensitive: false),
        ),
      ),
      findsNothing,
    );
    handle.dispose();
  });

  testWidgets('a photo picked again while cached still shows its frame', (
    tester,
  ) async {
    final photo = quarters('cached', 400, 300);
    await openWith(tester, [photo]);
    await tester.pumpWidget(const SizedBox());

    await openWith(tester, [photo]);
    expect(tester.takeException(), isNull);
    expect(framedImage, findsOneWidget);
  });

  testWidgets('a restored draft of a cached photo shows its frame', (
    tester,
  ) async {
    final photo = quarters('restored', 400, 300);
    await openWith(tester, [photo]);
    await tester.pumpWidget(const SizedBox());

    await openWith(tester, [photo], restored: true);
    expect(tester.takeException(), isNull);
    expect(framedImage, findsOneWidget);
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

class _NoSpaceFile extends Fake implements File {
  _NoSpaceFile(this.path);

  @override
  final String path;

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async => throw FileSystemException(
    'No space left on device',
    path,
    const OSError('No space left on device', 28),
  );
}
