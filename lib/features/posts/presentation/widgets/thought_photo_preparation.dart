import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_app/features/posts/application/post_media_draft.dart';
import 'package:path_provider/path_provider.dart';

enum ThoughtPhotoFraming { fit, fillScreen }

/// Owns only the crop files made by one preview's Apply operation.
class PreparedThoughtPhotos {
  final List<PostMediaDraft> drafts;
  final Directory? _cropDirectory;

  PreparedThoughtPhotos._(this.drafts, this._cropDirectory);

  /// The composer calls this only when it cannot adopt the preview result.
  Future<void> discard() async {
    final directory = _cropDirectory;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

Future<PreparedThoughtPhotos> prepareThoughtPhotos(
  List<PostMediaDraft> drafts,
  List<ThoughtPhotoFraming> framing, {
  required double aspectRatio,
}) async {
  if (!aspectRatio.isFinite ||
      aspectRatio <= 0 ||
      aspectRatio > 1 ||
      drafts.length != framing.length ||
      drafts.any((draft) => draft.kind != 'image')) {
    throw ArgumentError('Photo framing must match the selected photos.');
  }
  Directory? cropDirectory;
  final prepared = <PostMediaDraft>[];
  try {
    for (var index = 0; index < drafts.length; index++) {
      final draft = drafts[index];
      if (framing[index] == ThoughtPhotoFraming.fit) {
        prepared.add(draft);
        continue;
      }
      cropDirectory ??= await (await getTemporaryDirectory()).createTemp(
        'thought-photo-crop-',
      );
      prepared.add(
        await _fillScreen(
          draft,
          '${cropDirectory.path}/photo-$index.png',
          aspectRatio,
        ),
      );
    }
    return PreparedThoughtPhotos._(
      List<PostMediaDraft>.unmodifiable(prepared),
      cropDirectory,
    );
  } on Object {
    if (cropDirectory != null && await cropDirectory.exists()) {
      await cropDirectory.delete(recursive: true);
    }
    rethrow;
  }
}

Future<PostMediaDraft> _fillScreen(
  PostMediaDraft draft,
  String output,
  double aspectRatio,
) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  ui.Picture? picture;
  ui.Image? cropped;
  try {
    buffer = await ui.ImmutableBuffer.fromFilePath(draft.localFilePath);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    // This editor bounds its returned raster to 4096px per side, without
    // upscaling. Native codecs can still use transient decode working memory.
    const maxSide = 4096;
    final scale = math.min(
      1.0,
      maxSide / math.max(descriptor.width, descriptor.height),
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * scale).round()),
      targetHeight: math.max(1, (descriptor.height * scale).round()),
    );
    image = (await codec.getNextFrame()).image;
    final cropHeight = math.min(
      image.height.toDouble(),
      image.width / aspectRatio,
    );
    final cropWidth = cropHeight * aspectRatio;
    final width = math.max(1, cropWidth.round());
    final height = math.max(1, cropHeight.round());
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      image,
      ui.Rect.fromLTWH(
        (image.width - cropWidth) / 2,
        (image.height - cropHeight) / 2,
        cropWidth,
        cropHeight,
      ),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint(),
    );
    picture = recorder.endRecording();
    cropped = await picture.toImage(width, height);
    final png = await cropped.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw StateError('Could not encode the cropped photo.');
    await File(output).writeAsBytes(
      png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      flush: true,
    );
    return PostMediaDraft(
      localFilePath: output,
      mime: 'image/png',
      width: width,
      height: height,
    );
  } finally {
    cropped?.dispose();
    picture?.dispose();
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}
