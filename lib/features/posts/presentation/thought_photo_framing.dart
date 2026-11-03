import 'dart:ui';

import 'package:flutter_app/features/posts/application/post_media_draft.dart';

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
  Rect cropRect(Size photo) => Rect.zero;

  /// The framing after a gesture that began at [from] in a frame of
  /// [frameSide] and is now at [to], zoomed by [zoom] since it began.
  PhotoFraming pinched(
    Size photo,
    double frameSide, {
    required Offset from,
    required Offset to,
    double zoom = 1,
  }) => this;
}

/// The framed square of [draft]'s photo as a new JPEG of at most [maxSide]
/// pixels a side.
Future<PostMediaDraft> bakeFramedPhoto(
  PostMediaDraft draft,
  PhotoFraming framing, {
  int maxSide = 1440,
}) async => draft;
