import 'dart:io';
import 'dart:typed_data';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_app/features/posts/application/post_media_draft.dart';
import 'package:image/image.dart' as img;

/// Where a Thought photo sits in the composer's square frame. [scale] 1 is
/// the photo just covering the square, and it zooms out to the whole photo
/// inside the square; [center] is the square's centre on the photo, as
/// fractions of the photo's width and height.
class PhotoFraming {
  const PhotoFraming({this.scale = 1, this.center = const Offset(.5, .5)});

  static const cover = PhotoFraming();
  static const maxScale = 4.0;

  final double scale;
  final Offset center;

  /// The scale at which the whole photo just fits in the square.
  static double wholeScale(Size photo) =>
      photo.shortestSide / photo.longestSide;

  double _scaleOn(Size photo) => scale.clamp(wholeScale(photo), maxScale);

  /// The framed square on a photo of [photo] pixels, as displayed (EXIF
  /// orientation already applied). Along a side longer than the square it
  /// never passes the photo's edges; along a shorter side the photo sits
  /// centred in it.
  Rect cropRect(Size photo) {
    final side = photo.shortestSide / _scaleOn(photo);
    double place(double fraction, double extent) => side >= extent
        ? extent / 2
        : (fraction * extent).clamp(side / 2, extent - side / 2);
    return Rect.fromCenter(
      center: Offset(
        place(center.dx, photo.width),
        place(center.dy, photo.height),
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
    final nextScale = (_scaleOn(photo) * zoom).clamp(
      wholeScale(photo),
      maxScale,
    );
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
/// photo is drawn on [photoEdgeColor], as the composer's preview is. The
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
      final framed = framing
          .cropRect(Size(width.toDouble(), height.toDouble()))
          .width;
      return thoughtDecodeSize(width, height, maxSide / framed);
    },
  );
  final matte = await photoEdgeColor(draft.localFilePath);
  final ui.Image photo;
  try {
    photo = (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
  final ui.Image square;
  try {
    final size = Size(photo.width.toDouble(), photo.height.toDouble());
    final crop = framing.cropRect(size);
    final side = math.max(1, math.min(maxSide, crop.width.round()));
    final zoom = side / crop.width;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..drawColor(matte, ui.BlendMode.src);
    canvas.drawImageRect(
      photo,
      Offset.zero & size,
      Rect.fromLTWH(
        -crop.left * zoom,
        -crop.top * zoom,
        size.width * zoom,
        size.height * zoom,
      ),
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

/// One colour for the empty part of the square when a photo is zoomed out:
/// the average of the outer pixels along the two long edges, the ones that
/// face the empty part. The composer's preview and the bake both use it, so
/// friends see the colour the author saw.
Future<ui.Color> photoEdgeColor(String path) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(
    await File(path).readAsBytes(),
  );
  final codec = await ui.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (width, height) => thoughtDecodeSize(
      width,
      height,
      _edgeSampleSide / math.max(width, height),
    ),
  );
  final ui.Image image;
  try {
    image = (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
  final width = image.width;
  final height = image.height;
  final ByteData? rgba;
  try {
    rgba = await image.toByteData();
  } finally {
    image.dispose();
  }
  if (rgba == null) throw StateError('Photo has no pixels');
  final wide = width >= height;
  final depth = math.min(_edgeDepth, wide ? height : width);
  var r = 0, g = 0, b = 0, n = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final along = wide ? y : x;
      final extent = wide ? height : width;
      if (along >= depth && along < extent - depth) continue;
      final i = (y * width + x) * 4;
      r += rgba.getUint8(i);
      g += rgba.getUint8(i + 1);
      b += rgba.getUint8(i + 2);
      n++;
    }
  }
  return ui.Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
}

/// The size to decode a [width] x [height] photo at when it is shrunk by
/// [shrink]: never upscaled, at least one pixel a side, and never thinner
/// than [_thinnestDecode] pixels where the photo is thicker, so a long thin
/// strip keeps its exact shape for framing.
ui.TargetImageSize thoughtDecodeSize(int width, int height, double shrink) {
  final floor = _thinnestDecode / math.max(1, math.min(width, height));
  final scale = math.min(1.0, math.max(shrink, floor));
  return ui.TargetImageSize(
    width: math.max(1, (width * scale).round()),
    height: math.max(1, (height * scale).round()),
  );
}

const _thinnestDecode = 64;
const _edgeSampleSide = 256;
const _edgeDepth = 3;
