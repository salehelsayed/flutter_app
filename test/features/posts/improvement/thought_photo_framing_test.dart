import 'dart:io';
import 'dart:ui';

import 'package:flutter_app/features/posts/application/post_media_draft.dart';
import 'package:flutter_app/features/posts/presentation/thought_photo_framing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cropRect', () {
    test('a centred cover of a 4000x3000 landscape is its middle square', () {
      expect(
        PhotoFraming.cover.cropRect(const Size(4000, 3000)),
        const Rect.fromLTWH(500, 0, 3000, 3000),
      );
    });

    test('a centred cover of a 3000x4000 portrait is its middle square', () {
      expect(
        PhotoFraming.cover.cropRect(const Size(3000, 4000)),
        const Rect.fromLTWH(0, 500, 3000, 3000),
      );
    });

    test('2x placed at the top left takes the top-left quarter square', () {
      expect(
        const PhotoFraming(
          scale: 2,
          center: Offset.zero,
        ).cropRect(const Size(4000, 3000)),
        const Rect.fromLTWH(0, 0, 1500, 1500),
      );
    });

    test('scale clamps between the whole photo and 4x, and placement keeps '
        'the photo in the square', () {
      const photo = Size(4000, 3000);
      expect(
        const PhotoFraming(scale: .5, center: Offset(2, -1)).cropRect(photo),
        const Rect.fromLTWH(0, -500, 4000, 4000),
      );
      expect(
        const PhotoFraming(scale: 2, center: Offset(2, -1)).cropRect(photo),
        const Rect.fromLTWH(2500, 0, 1500, 1500),
      );
      expect(
        const PhotoFraming(scale: 9, center: Offset(.5, .5)).cropRect(photo),
        const Rect.fromLTWH(1625, 1125, 750, 750),
      );
    });
  });

  group('zoomed out', () {
    test('a wide photo at its smallest shows whole with room above and '
        'below', () {
      expect(
        const PhotoFraming(scale: .75).cropRect(const Size(4000, 3000)),
        const Rect.fromLTWH(0, -500, 4000, 4000),
      );
    });

    test('a tall photo at its smallest shows whole with room at the sides', () {
      expect(
        const PhotoFraming(scale: .75).cropRect(const Size(3000, 4000)),
        const Rect.fromLTWH(-500, 0, 4000, 4000),
      );
    });

    test('between cover and whole, the photo stays centred across its short '
        'side and still moves along its long side', () {
      const photo = Size(4000, 3000);
      final out = PhotoFraming.cover.pinched(
        photo,
        300,
        from: const Offset(150, 150),
        to: const Offset(150, 150),
        zoom: .9,
      );
      expect(out.scale, closeTo(.9, 1e-9));
      final crop = out.cropRect(photo);
      expect(crop.width, closeTo(3000 / .9, 1e-6));
      expect(crop.center.dy, closeTo(1500, 1e-6));
      final moved = out.pinched(
        photo,
        300,
        from: Offset.zero,
        to: const Offset(-40, 40),
      );
      final shifted = moved.cropRect(photo);
      expect(shifted.center.dy, closeTo(1500, 1e-6));
      expect(shifted.center.dx, greaterThan(crop.center.dx));
      expect(shifted.right, lessThanOrEqualTo(4000 + 1e-6));
    });

    test('a pinch out stops at the whole photo', () {
      const photo = Size(4000, 3000);
      final out = PhotoFraming.cover.pinched(
        photo,
        300,
        from: const Offset(150, 150),
        to: const Offset(150, 150),
        zoom: .2,
      );
      expect(out.scale, .75);
      expect(out.cropRect(photo), const Rect.fromLTWH(0, -500, 4000, 4000));
    });
  });

  group('pinched', () {
    const photo = Size(4000, 3000);

    test('a 2x pinch keeps the photo point under the fingers', () {
      expect(
        PhotoFraming.cover
            .pinched(
              photo,
              300,
              from: const Offset(150, 150),
              to: const Offset(150, 150),
              zoom: 2,
            )
            .cropRect(photo),
        const Rect.fromLTWH(1250, 750, 1500, 1500),
      );
    });

    test('a drag moves the square the other way, up to the photo edge', () {
      final right = PhotoFraming.cover.pinched(
        photo,
        300,
        from: Offset.zero,
        to: const Offset(30, 0),
      );
      expect(right.cropRect(photo), const Rect.fromLTWH(200, 0, 3000, 3000));
      final farLeft = PhotoFraming.cover.pinched(
        photo,
        300,
        from: Offset.zero,
        to: const Offset(-500, 900),
      );
      expect(farLeft.cropRect(photo), const Rect.fromLTWH(1000, 0, 3000, 3000));
      expect(farLeft.center, const Offset(.625, .5));
    });
  });

  group('bakeFramedPhoto', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('frame131_'));
    tearDown(() => dir.deleteSync(recursive: true));

    /// Red, green, blue and yellow quarters, top left to bottom right.
    String quarters(int width, int height, {int? exifOrientation}) {
      final image = img.Image(width: width, height: height);
      for (final pixel in image) {
        final right = pixel.x >= width / 2;
        final bottom = pixel.y >= height / 2;
        pixel
          ..r = right == bottom ? 255 : 0
          ..g = right ? 255 : 0
          ..b = !right && bottom ? 255 : 0;
      }
      if (exifOrientation != null) {
        image.exif.imageIfd.orientation = exifOrientation;
      }
      final path = '${dir.path}/source_${width}x$height.jpg';
      File(path).writeAsBytesSync(img.encodeJpg(image, quality: 95));
      return path;
    }

    /// [quarters] inside a [border]-pixel frame of rgb(40, 120, 200).
    String framed(int width, int height, {int border = 24}) {
      final image = img.Image(width: width, height: height);
      for (final pixel in image) {
        final edge =
            pixel.x < border ||
            pixel.y < border ||
            pixel.x >= width - border ||
            pixel.y >= height - border;
        final right = pixel.x >= width / 2;
        final bottom = pixel.y >= height / 2;
        pixel
          ..r = edge ? 40 : (right == bottom ? 255 : 0)
          ..g = edge ? 120 : (right ? 255 : 0)
          ..b = edge ? 200 : (!right && bottom ? 255 : 0);
      }
      final path = '${dir.path}/framed_${width}x$height.jpg';
      File(path).writeAsBytesSync(img.encodeJpg(image, quality: 95));
      return path;
    }

    void edgeColoured(img.Image image, int x, int y) {
      final p = image.getPixel(x, y);
      expect(
        [p.r, p.g, p.b],
        [
          inInclusiveRange(30, 50),
          inInclusiveRange(110, 130),
          inInclusiveRange(190, 210),
        ],
        reason: 'pixel $x,$y',
      );
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

    Future<img.Image> baked(PostMediaDraft draft) async {
      expect(draft.mime, 'image/jpeg');
      final bytes = File(draft.localFilePath).readAsBytesSync();
      expect(bytes.sublist(0, 2), [0xFF, 0xD8]);
      final image = img.decodeJpg(bytes)!;
      expect([draft.width, draft.height], [image.width, image.height]);
      return image;
    }

    test('a centred cover of a large landscape is a 1440 square of its '
        'middle', () async {
      final source = quarters(2000, 1500);
      final draft = await bakeFramedPhoto(
        PostMediaDraft(localFilePath: source, mime: 'image/jpeg'),
        PhotoFraming.cover,
      );
      expect(draft.localFilePath, isNot(source));
      final out = await baked(draft);
      expect([out.width, out.height], [1440, 1440]);
      expect(
        [
          colour(out, 8, 8),
          colour(out, 1431, 8),
          colour(out, 8, 1431),
          colour(out, 1431, 1431),
        ],
        ['red', 'green', 'blue', 'yellow'],
      );
      // The source's middle column (x 1000 of 250..1750) lands at x 720.
      expect([colour(out, 700, 8), colour(out, 740, 8)], ['red', 'green']);
    });

    test(
      'an EXIF-rotated portrait is framed upright, never upscaled',
      () async {
        final source = quarters(400, 300, exifOrientation: 6);
        final out = await baked(
          await bakeFramedPhoto(
            PostMediaDraft(localFilePath: source, mime: 'image/jpeg'),
            PhotoFraming.cover,
          ),
        );
        expect([out.width, out.height], [300, 300]);
        expect(
          [
            colour(out, 8, 8),
            colour(out, 291, 8),
            colour(out, 8, 291),
            colour(out, 291, 291),
          ],
          ['blue', 'red', 'yellow', 'green'],
        );
      },
    );

    test(
      'the edge colour is the average of the edges that face the bands',
      () async {
        final colour = await photoEdgeColor(framed(400, 300));
        expect(
          [
            (colour.r * 255).round(),
            (colour.g * 255).round(),
            (colour.b * 255).round(),
          ],
          [
            inInclusiveRange(30, 50),
            inInclusiveRange(110, 130),
            inInclusiveRange(190, 210),
          ],
        );
      },
    );

    test('a wide photo zoomed all the way out bakes whole, with bands of its '
        'edge colour above and below', () async {
      final out = await baked(
        await bakeFramedPhoto(
          PostMediaDraft(localFilePath: framed(400, 300), mime: 'image/jpeg'),
          const PhotoFraming(scale: .75),
        ),
      );
      expect([out.width, out.height], [400, 400]);
      for (final (x, y) in const [(8, 8), (200, 30), (391, 391), (200, 370)]) {
        edgeColoured(out, x, y);
      }
      expect(
        [
          colour(out, 40, 90),
          colour(out, 359, 90),
          colour(out, 40, 309),
          colour(out, 359, 309),
        ],
        ['red', 'green', 'blue', 'yellow'],
      );
    });

    test('a tall photo zoomed all the way out bakes whole, with bands at the '
        'sides', () async {
      final out = await baked(
        await bakeFramedPhoto(
          PostMediaDraft(localFilePath: framed(300, 400), mime: 'image/jpeg'),
          const PhotoFraming(scale: .75),
        ),
      );
      expect([out.width, out.height], [400, 400]);
      for (final (x, y) in const [(8, 200), (30, 8), (391, 200), (370, 391)]) {
        edgeColoured(out, x, y);
      }
      expect(
        [
          colour(out, 90, 40),
          colour(out, 309, 40),
          colour(out, 90, 359),
          colour(out, 309, 359),
        ],
        ['red', 'green', 'blue', 'yellow'],
      );
    });

    test(
      'a 5000x1 strip and a 1x5000 strip bake whole as a 1440 square',
      () async {
        for (final (width, height) in const [(5000, 1), (1, 5000)]) {
          final image = img.Image(width: width, height: height);
          for (final pixel in image) {
            pixel
              ..r = 40
              ..g = 120
              ..b = 200;
          }
          final path = '${dir.path}/strip_${width}x$height.png';
          File(path).writeAsBytesSync(img.encodePng(image));
          final out = await baked(
            await bakeFramedPhoto(
              PostMediaDraft(localFilePath: path, mime: 'image/png'),
              const PhotoFraming(scale: 0),
            ),
          );
          expect([out.width, out.height], [1440, 1440]);
          edgeColoured(out, 8, 8);
        }
      },
    );

    test('a photo with a see-through middle bakes on its edge colour, as the '
        'preview shows it', () async {
      final image = img.Image(width: 400, height: 300, numChannels: 4);
      for (final pixel in image) {
        final edge =
            pixel.x < 24 || pixel.y < 24 || pixel.x >= 376 || pixel.y >= 276;
        pixel
          ..r = 40
          ..g = 120
          ..b = 200
          ..a = edge ? 255 : 0;
      }
      final path = '${dir.path}/hole.png';
      File(path).writeAsBytesSync(img.encodePng(image));
      final out = await baked(
        await bakeFramedPhoto(
          PostMediaDraft(localFilePath: path, mime: 'image/png'),
          PhotoFraming.cover,
        ),
      );
      edgeColoured(out, 150, 150);
    });

    test(
      'a hair under cover still fills the thin band with the edge colour',
      () async {
        final image = img.Image(width: 400, height: 300);
        final path = '${dir.path}/black.png';
        File(path).writeAsBytesSync(img.encodePng(image));
        final out = await baked(
          await bakeFramedPhoto(
            PostMediaDraft(localFilePath: path, mime: 'image/png'),
            const PhotoFraming(scale: .998),
          ),
        );
        for (final x in const [0, 100, 200, 299]) {
          final p = out.getPixel(x, 0);
          expect([p.r, p.g, p.b], everyElement(lessThan(12)), reason: 'x $x');
        }
      },
    );

    test('a 2x top-left framing keeps only the top-left quarter at its own '
        'resolution', () async {
      final source = quarters(2000, 1500);
      final out = await baked(
        await bakeFramedPhoto(
          PostMediaDraft(localFilePath: source, mime: 'image/jpeg'),
          const PhotoFraming(scale: 2, center: Offset.zero),
        ),
      );
      expect([out.width, out.height], [750, 750]);
      expect(
        [
          colour(out, 8, 8),
          colour(out, 741, 8),
          colour(out, 8, 741),
          colour(out, 741, 741),
        ],
        ['red', 'red', 'red', 'red'],
      );
    });
  });
}
