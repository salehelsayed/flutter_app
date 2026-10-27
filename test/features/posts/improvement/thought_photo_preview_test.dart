import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_app/features/posts/application/post_media_draft.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/presentation/widgets/compose_post_sheet.dart';
import 'package:flutter_app/features/posts/presentation/widgets/thought_photo_preparation.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PathProviderPlatform previousPaths;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('thought-photo-test-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = previousPaths;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await root.delete(recursive: true);
  });

  PostMediaDraft photo(String name, {bool portrait = false}) {
    final image = img.Image(width: portrait ? 4 : 8, height: portrait ? 8 : 4);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final along = portrait ? y : x;
        image.setPixelRgb(
          x,
          y,
          along < 2 ? 255 : 0,
          along >= 2 && along < 6 ? 255 : 0,
          along >= 6 ? 255 : 0,
        );
      }
    }
    final file = File('${root.path}/$name.png')
      ..writeAsBytesSync(img.encodePng(image));
    return PostMediaDraft(
      localFilePath: file.path,
      mime: 'image/png',
      width: image.width,
      height: image.height,
    );
  }

  test(
    'Fit preserves original drafts, bytes and order without crop files',
    () async {
      final first = photo('first');
      final second = photo('second', portrait: true);
      final originalBytes = File(first.localFilePath).readAsBytesSync();

      final result = await prepareThoughtPhotos(
        [first, second],
        [ThoughtPhotoFraming.fit, ThoughtPhotoFraming.fit],
        aspectRatio: 0.5,
      );

      expect(result.drafts[0], same(first));
      expect(result.drafts[1], same(second));
      expect(File(first.localFilePath).readAsBytesSync(), originalBytes);
      expect(root.listSync().whereType<Directory>(), isEmpty);
      await result.discard();
      expect(File(first.localFilePath).existsSync(), isTrue);
    },
  );

  for (final portrait in [false, true]) {
    test(
      'Fill screen exports the displayed portrait crop (${portrait ? 'portrait' : 'landscape'})',
      () async {
        final original = photo('source', portrait: portrait);
        final bytes = File(original.localFilePath).readAsBytesSync();
        final result = await prepareThoughtPhotos(
          [original],
          [ThoughtPhotoFraming.fillScreen],
          aspectRatio: 0.5,
        );
        final crop = result.drafts.single;
        expect(crop.localFilePath, isNot(original.localFilePath));
        expect(crop.mime, 'image/png');
        expect((crop.width, crop.height), portrait ? (4, 8) : (2, 4));
        final output = img.decodePng(
          File(crop.localFilePath).readAsBytesSync(),
        )!;
        expect((output.width, output.height), portrait ? (4, 8) : (2, 4));
        final displayed = img.decodePng(bytes)!;
        final left = (displayed.width - output.width) ~/ 2;
        for (var y = 0; y < output.height; y++) {
          for (var x = 0; x < output.width; x++) {
            final actual = output.getPixel(x, y);
            final expected = displayed.getPixel(left + x, y);
            expect(
              [actual.r, actual.g, actual.b],
              [expected.r, expected.g, expected.b],
            );
          }
        }
        expect(File(original.localFilePath).readAsBytesSync(), bytes);
        await result.discard();
        expect(File(crop.localFilePath).existsSync(), isFalse);
        expect(File(original.localFilePath).existsSync(), isTrue);
      },
    );
  }

  for (final orientation in [2, 5, 6, 8]) {
    test('Crop follows Flutter display orientation $orientation', () async {
      final source = img.Image(width: 8, height: 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 8; x++) {
          source.setPixelRgb(x, y, x * 30, y * 60, (x + y) * 20);
        }
      }
      source.exif.imageIfd.orientation = orientation;
      final input = File('${root.path}/oriented.jpg')
        ..writeAsBytesSync(img.encodeJpg(source, quality: 100));
      final displayed = await _decodedPixels(input.readAsBytesSync());
      final result = await prepareThoughtPhotos(
        [PostMediaDraft(localFilePath: input.path, mime: 'image/jpeg')],
        [ThoughtPhotoFraming.fillScreen],
        aspectRatio: 0.5,
      );
      final output = await _decodedPixels(
        File(result.drafts.single.localFilePath).readAsBytesSync(),
      );
      final expectedWidth = displayed.width == 8 ? 2 : 4;
      final expectedHeight = displayed.height;
      expect((output.width, output.height), (expectedWidth, expectedHeight));
      // Compare against display pixels after the decoder applies EXIF.
      final left = (displayed.width - expectedWidth) ~/ 2;
      const top = 0;
      for (var y = 0; y < expectedHeight; y++) {
        for (var x = 0; x < expectedWidth; x++) {
          expect(output.pixel(x, y), displayed.pixel(left + x, top + y));
        }
      }
      await result.discard();
    });
  }

  test(
    'mixed framing preserves photo order and leaves Fit originals alone',
    () async {
      final first = photo('first');
      final second = photo('second');
      final third = photo('third');
      final result = await prepareThoughtPhotos(
        [first, second, third],
        [
          ThoughtPhotoFraming.fit,
          ThoughtPhotoFraming.fillScreen,
          ThoughtPhotoFraming.fit,
        ],
        aspectRatio: 0.5,
      );
      expect(result.drafts.first, same(first));
      expect(result.drafts.last, same(third));
      expect(result.drafts[1].localFilePath, isNot(second.localFilePath));
      expect(File(second.localFilePath).existsSync(), isTrue);
      await result.discard();
    },
  );

  test(
    'a later decode failure removes only this apply attempt\'s crop files',
    () async {
      final first = photo('first');
      final broken = File('${root.path}/broken.heic')
        ..writeAsStringSync('not a photo');
      await expectLater(
        prepareThoughtPhotos(
          [
            first,
            PostMediaDraft(localFilePath: broken.path, mime: 'image/heic'),
          ],
          [ThoughtPhotoFraming.fillScreen, ThoughtPhotoFraming.fillScreen],
          aspectRatio: 0.5,
        ),
        throwsA(isA<Object>()),
      );
      expect(root.listSync().whereType<Directory>(), isEmpty);
      expect(File(first.localFilePath).existsSync(), isTrue);
      expect(broken.readAsStringSync(), 'not a photo');
    },
  );

  Widget scene({
    required List<PostMediaDraft> photos,
    required Future<ComposePostSubmitOutcome> Function(ComposePostResult)
    submit,
    ValueChanged<ComposePostResult?>? onClosed,
    Locale locale = const Locale('en'),
  }) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ComposePostSheet(
        thoughtsOnly: true,
        eligibleContacts: const [],
        replacesCurrentThought: true,
        initialDraft: ComposePostResult(
          text: 'My caption',
          audience: PostAudience.allFriends(),
          mediaDrafts: const [],
        ),
        onAttachMedia: () async => photos,
        onSubmitWithOutcome: submit,
        onClosed: onClosed,
      ),
    ),
  );

  Future<void> openPreview(WidgetTester tester) async {
    final action = find.byIcon(Icons.photo_library_outlined);
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
  }

  Future<void> applyPhotos(WidgetTester tester) async {
    final action = find.byKey(const ValueKey('thought-photo-use'));
    await tester.ensureVisible(action);
    final callback = tester.widget<FilledButton>(action).onPressed!;
    // Await the real registered async handler so codec and filesystem work
    // completes outside the widget test's fake clock.
    await tester.runAsync(() async => await Function.apply(callback, const []));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'automatic preview Cancel discards the new pick and preserves text',
    (tester) async {
      final original = photo('cancelled');
      ComposePostResult? submitted;
      await tester.pumpWidget(
        scene(
          photos: [original],
          submit: (draft) async {
            submitted = draft;
            return ComposePostSubmitOutcome.keepSheetOpen;
          },
        ),
      );
      await openPreview(tester);
      expect(find.byKey(const ValueKey('thought-photo-use')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('thought-composer-preview-photos')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('thought-photo-cancel')));
      await tester.pumpAndSettle();
      final share = find.byKey(const ValueKey('thought-composer-share'));
      await tester.ensureVisible(share);
      await tester.tap(share);
      await tester.pump();
      expect(submitted!.text, 'My caption');
      expect(submitted!.mediaDrafts, isEmpty);
      expect(File(original.localFilePath).existsSync(), isTrue);
      expect(root.listSync().whereType<Directory>(), isEmpty);
    },
  );

  testWidgets(
    'preview Fit and Cancel keep the caption, originals and lifetime lines',
    (tester) async {
      final original = photo('original');
      ComposePostResult? submitted;
      await tester.pumpWidget(
        scene(
          photos: [original],
          submit: (draft) async {
            submitted = draft;
            return ComposePostSubmitOutcome.keepSheetOpen;
          },
        ),
      );
      await openPreview(tester);
      expect(
        find.byKey(const ValueKey('thought-photo-lifetime')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('thought-photo-replaces')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('thought-photo-fit')))
            .selected,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('thought-photo-crop')));
      await tester.pump();
      expect(
        tester
            .widget<Image>(find.byKey(const ValueKey('thought-photo-page-0')))
            .fit,
        BoxFit.cover,
      );
      await tester.tap(find.byKey(const ValueKey('thought-photo-fit')));
      await applyPhotos(tester);
      expect(find.text('My caption'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('thought-composer-lifetime')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('thought-composer-replaces')),
        findsOneWidget,
      );

      await openPreview(tester);
      await tester.tap(find.byKey(const ValueKey('thought-photo-crop')));
      await tester.tap(find.byKey(const ValueKey('thought-photo-cancel')));
      await tester.pumpAndSettle();
      final share = find.byKey(const ValueKey('thought-composer-share'));
      await tester.ensureVisible(share);
      await tester.tap(share);
      await tester.pump();
      expect(submitted!.text, 'My caption');
      expect(submitted!.mediaDrafts.single, same(original));
      expect(root.listSync().whereType<Directory>(), isEmpty);
    },
  );

  testWidgets(
    'per-photo Crop/fit applies actual files in order and persists the draft',
    (tester) async {
      final first = photo('first');
      final second = photo('second', portrait: true);
      ComposePostResult? submitted;
      ComposePostResult? closed;
      await tester.pumpWidget(
        scene(
          photos: [first, second],
          submit: (draft) async {
            submitted = draft;
            return ComposePostSubmitOutcome.keepSheetOpen;
          },
          onClosed: (draft) => closed = draft,
        ),
      );
      await openPreview(tester);
      await tester.tap(find.byKey(const ValueKey('thought-photo-crop')));
      await tester.tap(find.byKey(const ValueKey('thought-photo-next')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('thought-photo-fit')))
            .selected,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('thought-photo-previous')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('thought-photo-crop')),
            )
            .selected,
        isTrue,
      );
      await applyPhotos(tester);
      final share = find.byKey(const ValueKey('thought-composer-share'));
      await tester.ensureVisible(share);
      await tester.tap(share);
      await tester.pump();
      final crop = submitted!.mediaDrafts.first;
      expect(crop.localFilePath, isNot(first.localFilePath));
      expect((crop.width, crop.height), (3, 4));
      expect(submitted!.mediaDrafts.last, same(second));
      expect(submitted!.text, 'My caption');
      await tester.pumpWidget(const SizedBox());
      expect(closed!.mediaDrafts.first.localFilePath, crop.localFilePath);
      expect(File(crop.localFilePath).existsSync(), isTrue);
      expect(File(first.localFilePath).existsSync(), isTrue);
    },
  );

  testWidgets(
    'failed Crop can retry as Fit without losing text or the original',
    (tester) async {
      final broken = File('${root.path}/broken.png')
        ..writeAsStringSync('broken');
      final original = PostMediaDraft(
        localFilePath: broken.path,
        mime: 'image/png',
      );
      ComposePostResult? submitted;
      await tester.pumpWidget(
        scene(
          photos: [original],
          submit: (draft) async {
            submitted = draft;
            return ComposePostSubmitOutcome.keepSheetOpen;
          },
        ),
      );
      await openPreview(tester);
      await tester.tap(find.byKey(const ValueKey('thought-photo-crop')));
      await applyPhotos(tester);
      expect(find.byKey(const ValueKey('thought-photo-error')), findsOneWidget);
      expect(root.listSync().whereType<Directory>(), isEmpty);
      await tester.tap(find.byKey(const ValueKey('thought-photo-fit')));
      await applyPhotos(tester);
      final share = find.byKey(const ValueKey('thought-composer-share'));
      await tester.ensureVisible(share);
      await tester.tap(share);
      await tester.pump();
      expect(submitted!.mediaDrafts.single, same(original));
      expect(submitted!.text, 'My caption');
    },
  );

  testWidgets('photo controls stay reachable in a small RTL viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final original = photo('rtl');
    await tester.pumpWidget(
      scene(
        photos: [original],
        locale: const Locale('ar'),
        submit: (_) async => ComposePostSubmitOutcome.keepSheetOpen,
      ),
    );
    await openPreview(tester);
    expect(
      Directionality.of(
        tester.element(find.byKey(const ValueKey('thought-photo-fit'))),
      ),
      TextDirection.rtl,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('thought-photo-crop')),
    );
    await tester.tap(find.byKey(const ValueKey('thought-photo-crop')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('thought-photo-cancel')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _Paths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String path;
  _Paths(this.path);

  @override
  Future<String?> getTemporaryPath() async => path;
}

Future<_Pixels> _decodedPixels(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  ui.Image? image;
  try {
    image = (await codec.getNextFrame()).image;
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return _Pixels(image.width, image.height, pixels!.buffer.asUint8List());
  } finally {
    image?.dispose();
    codec.dispose();
  }
}

class _Pixels {
  final int width;
  final int height;
  final Uint8List bytes;
  _Pixels(this.width, this.height, this.bytes);

  List<int> pixel(int x, int y) {
    final offset = (y * width + x) * 4;
    return bytes.sublist(offset, offset + 4);
  }
}
