import 'package:flutter/widgets.dart';

/// Wraps [inner] so an avatar decodes at [cacheSize] logical→device pixels while
/// PRESERVING its source aspect ratio.
///
/// 156 QW-4 decodes avatars at their on-screen pixel size to save memory, but it
/// set BOTH `cacheWidth` and `cacheHeight`, which defaults [ResizeImage] to
/// [ResizeImagePolicy.exact] — squashing a non-square source to a square bitmap
/// at decode time (that is the plan-200 stretch bug). [ResizeImagePolicy.fit]
/// keeps the bounded-decode memory win but scales to fit within the box without
/// distortion; the call site's `BoxFit.cover` inside a clip then cover-crops the
/// aspect-correct bitmap.
///
/// GIF sources must NOT be wrapped (ResizeImage collapses an animated GIF to its
/// first frame) — call sites pass a raw provider for the `.gif` branch.
ImageProvider avatarResizedProvider(ImageProvider inner, int cacheSize) {
  return ResizeImage(
    inner,
    width: cacheSize,
    height: cacheSize,
    policy: ResizeImagePolicy.fit,
  );
}
