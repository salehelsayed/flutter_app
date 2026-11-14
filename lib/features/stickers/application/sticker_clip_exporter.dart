import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/config/custom_stickers_flag.dart';
import 'package:flutter_app/features/stickers/application/animated_sticker_codec.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker_asset.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum StickerClipExportFailure {
  disabled,
  busy,
  invalidClip,
  budgetExceeded,
  unavailable,
  storageFailure,
}

final class StickerClipExportException implements Exception {
  const StickerClipExportException(this.failure);

  final StickerClipExportFailure failure;
}

/// Takes an app-owned silent camera clip and the editor's crop and overlay.
///
/// On success the caller owns the two files in the returned job directory and
/// cleans them after admission. Cancellation and failure clean only this job.
final class StickerClipExporter {
  StickerClipExporter({
    Future<Directory> Function() temporaryDirectory = getTemporaryDirectory,
  }) : _temporaryDirectory = temporaryDirectory;

  static const _channel = MethodChannel('mknoon/custom_sticker_clip_frames');
  static const _maxSourceBytes = 64 * 1024 * 1024;
  static bool _exporting = false;

  final Future<Directory> Function() _temporaryDirectory;
  _ExportJob? _job;

  Future<NormalizedStickerAsset?> export({
    required String clipPath,
    required Rect crop,
    required bool circle,
    Uint8List? textOverlay,
  }) async {
    if (!kCustomStickersEnabled) {
      throw const StickerClipExportException(StickerClipExportFailure.disabled);
    }
    if (_exporting) {
      throw const StickerClipExportException(StickerClipExportFailure.busy);
    }
    if (!p.isAbsolute(clipPath) ||
        !crop.isFinite ||
        crop.isEmpty ||
        crop.left < 0 ||
        crop.top < 0 ||
        crop.right > 1 ||
        crop.bottom > 1 ||
        (textOverlay != null &&
            textOverlay.length != stickerAnimationFrameBytes)) {
      throw const StickerClipExportException(
        StickerClipExportFailure.invalidClip,
      );
    }

    // Capture the editor result before the first asynchronous boundary.
    final overlay = textOverlay == null
        ? null
        : Uint8List.fromList(textOverlay);
    final job = _ExportJob();
    _exporting = true;
    _job = job;
    Directory? directory;
    var keep = false;
    try {
      final source = await File(clipPath).stat();
      if (source.type != FileSystemEntityType.file ||
          source.size <= 0 ||
          source.size > _maxSourceBytes) {
        throw const StickerClipExportException(
          StickerClipExportFailure.invalidClip,
        );
      }
      if (job.cancelled) return null;
      final cache = await _temporaryDirectory();
      if (job.cancelled) return null;
      directory = await cache.createTemp('mknoon-sticker-animation-');
      if (job.cancelled) return null;
      final jobId = p.basename(directory.path);
      job.id = jobId;
      final frames = File(p.join(directory.path, 'frames.rgba'));
      final native = await _extract(
        job,
        jobId: jobId,
        clipPath: clipPath,
        framesPath: frames.path,
        crop: crop,
      );
      if (job.cancelled) return null;
      final duration = native?['durationMs'];
      final frameCount = native?['frameCount'];
      if (duration is! int ||
          frameCount is! int ||
          frameCount != stickerAnimationSampleTimes(duration).length ||
          !await frames.exists() ||
          await frames.length() != frameCount * stickerAnimationFrameBytes) {
        throw const StickerClipExportException(
          StickerClipExportFailure.invalidClip,
        );
      }

      final encoded = await _encodeInWorker(
        job,
        framesPath: frames.path,
        frameCount: frameCount,
        durationMs: duration,
        circle: circle,
        overlay: overlay,
      );
      if (encoded == null || job.cancelled) return null;
      final canonical = File(p.join(directory.path, 'sticker.webp'));
      final poster = File(p.join(directory.path, 'poster.webp'));
      await canonical.writeAsBytes(encoded.webp, flush: true);
      if (job.cancelled) return null;
      await poster.writeAsBytes(encoded.poster, flush: true);
      await frames.delete();
      if (job.cancelled) return null;
      final asset = NormalizedStickerAsset(
        filePath: canonical.path,
        sha256Hex: sha256.convert(encoded.webp).toString(),
        mime: 'image/webp',
        byteLength: encoded.webp.length,
        width: stickerAnimationSide,
        height: stickerAnimationSide,
        frameCount: encoded.frameCount,
        durationMs: encoded.durationMs,
        posterPath: poster.path,
      );
      keep = true;
      return asset;
    } on AnimatedStickerCodecException catch (error) {
      if (job.cancelled) return null;
      throw StickerClipExportException(
        error.failure == AnimatedStickerCodecFailure.budgetExceeded
            ? StickerClipExportFailure.budgetExceeded
            : StickerClipExportFailure.invalidClip,
      );
    } on FileSystemException {
      if (job.cancelled) return null;
      throw const StickerClipExportException(
        StickerClipExportFailure.storageFailure,
      );
    } finally {
      try {
        if (!keep && directory != null && await directory.exists()) {
          await directory.delete(recursive: true);
        }
      } finally {
        _job = null;
        _exporting = false;
        job.finished.complete();
      }
    }
  }

  Future<void> cancel() async {
    final job = _job;
    if (job == null) return;
    if (job.cancelled) return job.finished.future;
    job.cancelled = true;
    job.stopEncoding?.call();
    if (job.extracting) {
      try {
        await _channel.invokeMethod<void>('cancel', {'jobId': job.id});
      } on PlatformException {
        // The export still joins the extraction response before cleanup.
      } on MissingPluginException {
        // A detached engine can no longer receive the cancellation request.
      }
    }
    await job.finished.future;
  }

  Future<Map<String, Object?>?> _extract(
    _ExportJob job, {
    required String jobId,
    required String clipPath,
    required String framesPath,
    required Rect crop,
  }) async {
    job.extracting = true;
    try {
      return await _channel.invokeMapMethod<String, Object?>('extract', {
        'jobId': jobId,
        'clipPath': clipPath,
        'framesPath': framesPath,
        'crop': [crop.left, crop.top, crop.right, crop.bottom],
      });
    } on PlatformException catch (error) {
      if (job.cancelled || error.code == 'cancelled') {
        job.cancelled = true;
        return null;
      }
      throw StickerClipExportException(
        error.code == 'invalid_clip'
            ? StickerClipExportFailure.invalidClip
            : StickerClipExportFailure.unavailable,
      );
    } on MissingPluginException {
      if (job.cancelled) return null;
      throw const StickerClipExportException(
        StickerClipExportFailure.unavailable,
      );
    } finally {
      job.extracting = false;
    }
  }
}

final class _ExportJob {
  final finished = Completer<void>();
  bool cancelled = false;
  bool extracting = false;
  String? id;
  void Function()? stopEncoding;
}

typedef _EncodeRequest = ({
  SendPort reply,
  String framesPath,
  int frameCount,
  int durationMs,
  bool circle,
  Uint8List? overlay,
});

Future<EncodedStickerAnimation?> _encodeInWorker(
  _ExportJob job, {
  required String framesPath,
  required int frameCount,
  required int durationMs,
  required bool circle,
  required Uint8List? overlay,
}) async {
  final port = ReceivePort();
  final response = port.first;
  Isolate? isolate;
  try {
    final worker = await Isolate.spawn(
      _runCodec,
      (
        reply: port.sendPort,
        framesPath: framesPath,
        frameCount: frameCount,
        durationMs: durationMs,
        circle: circle,
        overlay: overlay,
      ),
      onError: port.sendPort,
      onExit: port.sendPort,
    );
    isolate = worker;
    job.stopEncoding = () => worker.kill(priority: Isolate.immediate);
    if (job.cancelled) job.stopEncoding!();
    final result = await response;
    if (job.cancelled) return null;
    if (result is AnimatedStickerCodecException) throw result;
    if (result is EncodedStickerAnimation) return result;
    throw const StickerClipExportException(
      StickerClipExportFailure.unavailable,
    );
  } finally {
    job.stopEncoding = null;
    isolate?.kill(priority: Isolate.immediate);
    port.close();
  }
}

void _runCodec(_EncodeRequest request) {
  try {
    final expectedBytes = request.frameCount * stickerAnimationFrameBytes;
    final file = File(request.framesPath).openSync();
    final Uint8List bytes;
    try {
      bytes = file.readSync(expectedBytes + 1);
    } finally {
      file.closeSync();
    }
    if (bytes.length != expectedBytes) {
      throw const AnimatedStickerCodecException(
        AnimatedStickerCodecFailure.invalidInput,
      );
    }
    final frames = List.generate(
      request.frameCount,
      (i) => Uint8List.sublistView(
        bytes,
        i * stickerAnimationFrameBytes,
        (i + 1) * stickerAnimationFrameBytes,
      ),
    );
    Isolate.exit(
      request.reply,
      encodeStickerAnimation(
        croppedFrames: frames,
        durationMs: request.durationMs,
        circle: request.circle,
        textOverlay: request.overlay,
      ),
    );
  } on AnimatedStickerCodecException catch (error) {
    Isolate.exit(request.reply, error);
  }
}
