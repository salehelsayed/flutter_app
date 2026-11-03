import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_app/features/posts/application/post_media_draft.dart';
import 'package:image/image.dart' as img;

/// Where a Thought photo sits in the composer's square frame. [scale] 1 is
/// the photo just covering the square; [center] is the square's centre on
/// the photo, as fractions of the photo's width and height.
class PhotoFraming {
  const PhotoFraming({this.scale = 1, this.center = const Offset(.5, .5)});

  static const cover = PhotoFraming();
  static const maxScale = 4.0;

  final double scale;
  final Offset center;

  /// The framed square on a photo of [photo] pixels, as displayed (EXIF
  /// orientation already applied), never past the photo's edges.
  Rect cropRect(Size photo) {
    final side = photo.shortestSide / scale.clamp(1.0, maxScale);
    final half = side / 2;
    return Rect.fromCenter(
      center: Offset(
        (center.dx * photo.width).clamp(half, photo.width - half),
        (center.dy * photo.height).clamp(half, photo.height - half),
      ),
      width: side,
      height: side,
    );
  }

  /// The framing after a gesture that began at [from] in a frame of
  /// [frameSide] and is now at [to], zoomed by [zoom] since it began.
  PhotoFraming pinched(
    Size photo,
    double frameSide, {
    required Offset from,
    required Offset to,
    double zoom = 1,
  }) {
    final start = cropRect(photo);
    final anchor = start.topLeft + from * (start.width / frameSide);
    final nextScale = (scale.clamp(1.0, maxScale) * zoom).clamp(1.0, maxScale);
    final side = photo.shortestSide / nextScale;
    final centre =
        anchor - to * (side / frameSide) + Offset(side / 2, side / 2);
    final settled = PhotoFraming(
      scale: nextScale,
      center: Offset(centre.dx / photo.width, centre.dy / photo.height),
    ).cropRect(photo).center;
    return PhotoFraming(
      scale: nextScale,
      center: Offset(settled.dx / photo.width, settled.dy / photo.height),
    );
  }
}

/// The framed square of [draft]'s photo as a new JPEG of at most [maxSide]
/// pixels a side, and never larger than the framed area of the source. The
/// engine decoder applies EXIF orientation, as the composer's preview does.
Future<PostMediaDraft> bakeFramedPhoto(
  PostMediaDraft draft,
  PhotoFraming framing, {
  int maxSide = 1440,
}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(
    await File(draft.localFilePath).readAsBytes(),
  );
  final codec = await ui.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (width, height) {
      final framed =
          math.min(width, height) /
          framing.scale.clamp(1.0, PhotoFraming.maxScale);
      final shrink = math.min(1.0, maxSide / framed);
      return ui.TargetImageSize(
        width: (width * shrink).round(),
        height: (height * shrink).round(),
      );
    },
  );
  final ui.Image photo;
  try {
    photo = (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
  final ui.Image square;
  try {
    final crop = framing.cropRect(
      Size(photo.width.toDouble(), photo.height.toDouble()),
    );
    final side = math.min(maxSide, crop.width.round());
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      photo,
      crop,
      Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    square = await picture.toImage(side, side);
    picture.dispose();
  } finally {
    photo.dispose();
  }
  final side = square.width;
  final rgba = await square.toByteData();
  square.dispose();
  if (rgba == null) throw StateError('Framed photo has no pixels');
  final jpeg = await Isolate.run(
    () => img.encodeJpg(
      img.Image.fromBytes(
        width: side,
        height: side,
        bytes: rgba.buffer,
        numChannels: 4,
      ),
      quality: 90,
    ),
  );
  final file = File(
    '${Directory.systemTemp.path}/thought_framed_'
    '${DateTime.now().microsecondsSinceEpoch}.jpg',
  );
  await file.writeAsBytes(jpeg, flush: true);
  return PostMediaDraft(
    localFilePath: file.path,
    mime: 'image/jpeg',
    width: side,
    height: side,
  );
}
