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

    test('scale and placement clamp so the square never leaves the photo', () {
      const photo = Size(4000, 3000);
      expect(
        const PhotoFraming(scale: .5, center: Offset(2, -1)).cropRect(photo),
        const Rect.fromLTWH(1000, 0, 3000, 3000),
      );
      expect(
        const PhotoFraming(scale: 9, center: Offset(.5, .5)).cropRect(photo),
        const Rect.fromLTWH(1625, 1125, 750, 750),
      );
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
