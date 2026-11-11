import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_app/features/stickers/application/custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/application/sticker_cutout.dart';
import 'package:flutter_app/features/stickers/custom/editor/sticker_still_export.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker_asset.dart';
import 'package:flutter_app/features/stickers/domain/sticker_editor_result.dart';

enum StickerCreateSource { cameraPhoto, cameraClip, galleryPhoto }

sealed class StickerCreateOutcome {
  const StickerCreateOutcome();
}

final class StickerCreateCancelled extends StickerCreateOutcome {
  const StickerCreateCancelled();
}

final class StickerCreateSaved extends StickerCreateOutcome {
  const StickerCreateSaved(this.sticker);
  final CustomSticker sticker;
}

final class StickerCreateFailed extends StickerCreateOutcome {
  const StickerCreateFailed(this.code);
  final CustomStickerErrorCode code;
}

/// A square crop chosen on a still: the cropped bytes and the chosen shape.
typedef StickerStillCrop = ({Uint8List bytes, StickerShape shape});

/// A square crop chosen on a clip, normalized on the orientation-corrected
/// frame, as the clip exporter expects.
typedef StickerClipCrop = ({Rect crop, bool circle});

/// Runs one Create attempt from source to library. Every step that shows UI
/// or touches the platform is injected, so the order and the fallbacks are
/// testable without cameras or pickers.
final class StickerCreateFlow {
  StickerCreateFlow({
    required this.library,
    required this.cutout,
    required this.pickPhoto,
    required this.captureClip,
    required this.readBytes,
    required this.deleteFile,
    required this.cropStill,
    required this.cropClip,
    required this.editStill,
    required this.exportClip,
    required this.showNoSubject,
  });

  final CustomStickerLibrary library;
  final StickerCutoutService cutout;

  /// Returns a caller-owned photo path, or null when the user backs out.
  final Future<String?> Function(StickerCreateSource source) pickPhoto;
  final Future<String?> Function() captureClip;
  final Future<Uint8List> Function(String path) readBytes;
  final Future<void> Function(String path) deleteFile;
  final Future<StickerStillCrop?> Function(String photoPath) cropStill;
  final Future<StickerClipCrop?> Function(String clipPath) cropClip;
  final Future<StickerEditorResult> Function(
    Uint8List bytes,
    StickerShape shape,
  )
  editStill;
  final Future<NormalizedStickerAsset?> Function(
    String clipPath,
    StickerClipCrop crop,
  )
  exportClip;
  final void Function() showNoSubject;

  bool _cancelled = false;

  Future<StickerCreateOutcome> run(StickerCreateSource source) async {
    _cancelled = false;
    final clip = source == StickerCreateSource.cameraClip;
    final input = clip ? await captureClip() : await pickPhoto(source);
    if (input == null) return const StickerCreateCancelled();
    NormalizedStickerAsset? asset;
    try {
      asset = clip ? await _clip(input) : await _still(input);
      if (asset == null || _cancelled) return const StickerCreateCancelled();
      return StickerCreateSaved(await library.admit(asset));
    } on CustomStickerException catch (error) {
      return StickerCreateFailed(error.code);
    } finally {
      if (asset != null) await deleteFile(asset.filePath);
      await deleteFile(input);
    }
  }

  /// Ends an in-flight cut-out with nothing saved and no message.
  Future<void> cancel() async {
    _cancelled = true;
    await cutout.cancel();
  }

  Future<NormalizedStickerAsset?> _still(String photo) async {
    if (await cutout.availability() != StickerCutoutAvailability.ready) {
      return _cropAndEdit(photo);
    }
    final StickerCutout? found;
    try {
      found = await cutout.extract(photo);
    } on StickerCutoutException {
      return _cropAndEdit(photo);
    }
    if (_cancelled) return null;
    if (found == null) {
      showNoSubject();
      return _cropAndEdit(photo);
    }
    try {
      final edited = await editStill(
        await readBytes(found.imagePath),
        StickerShape.square,
      );
      return edited is StickerEditorReady ? edited.asset : null;
    } finally {
      await deleteFile(found.imagePath);
    }
  }

  Future<NormalizedStickerAsset?> _cropAndEdit(String photo) async {
    final crop = await cropStill(photo);
    if (crop == null) return null;
    final edited = await editStill(crop.bytes, crop.shape);
    return edited is StickerEditorReady ? edited.asset : null;
  }

  Future<NormalizedStickerAsset?> _clip(String clip) async {
    final crop = await cropClip(clip);
    if (crop == null) return null;
    return exportClip(clip, crop);
  }
}
