import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:path/path.dart' as p;
import 'package:video_compress/video_compress.dart';

const _videoExtensions = {'mp4', 'mov', 'avi', 'mkv', 'm4v'};

/// Generates a thumbnail JPG for [videoPath] and returns the file.
///
/// Injectable seam: production uses [VideoCompress.getFileThumbnail]; tests
/// override it via [debugSetVideoThumbnailGenerator] to exercise the
/// generation-failure path deterministically (no platform channel).
typedef VideoThumbnailGenerator = Future<File> Function(String videoPath);

Future<File> _defaultThumbnailGenerator(String videoPath) =>
    VideoCompress.getFileThumbnail(videoPath, quality: 70, position: -1);

VideoThumbnailGenerator _thumbnailGenerator = _defaultThumbnailGenerator;

@visibleForTesting
void debugSetVideoThumbnailGenerator(VideoThumbnailGenerator? generator) {
  _thumbnailGenerator = generator ?? _defaultThumbnailGenerator;
}

bool isLikelyVideoPath(String path) {
  final dotIndex = path.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == path.length - 1) {
    return false;
  }
  final ext = path.substring(dotIndex + 1).toLowerCase();
  return _videoExtensions.contains(ext);
}

String derivedVideoThumbnailPath(String videoPath) {
  final directory = p.dirname(videoPath);
  final baseName = p.basenameWithoutExtension(videoPath);
  return p.join(directory, '$baseName.thumb.jpg');
}

class VideoThumbnailCache {
  VideoThumbnailCache._();

  static final Map<String, Future<String?>> _inFlight =
      <String, Future<String?>>{};

  static Future<String?> resolve(String videoPath) async {
    if (!isLikelyVideoPath(videoPath)) {
      return null;
    }

    final videoFile = File(videoPath);
    if (!await videoFile.exists()) {
      return null;
    }

    final preferredOutputPath = derivedVideoThumbnailPath(videoPath);
    final preferredOutputFile = File(preferredOutputPath);
    if (await preferredOutputFile.exists()) {
      return preferredOutputPath;
    }

    final existing = _inFlight[videoPath];
    if (existing != null) {
      return existing;
    }

    late final Future<String?> future;
    future = _generate(videoPath, preferredOutputPath).whenComplete(() {
      if (identical(_inFlight[videoPath], future)) {
        _inFlight.remove(videoPath);
      }
    });
    _inFlight[videoPath] = future;
    return future;
  }

  static Future<String?> _generate(
    String videoPath,
    String preferredOutputPath,
  ) async {
    try {
      final thumbnail = await _thumbnailGenerator(videoPath);
      final generatedPath = thumbnail.path;
      if (generatedPath == preferredOutputPath) {
        return generatedPath;
      }

      final preferredOutputFile = File(preferredOutputPath);
      try {
        await preferredOutputFile.parent.create(recursive: true);
        if (!await preferredOutputFile.exists()) {
          await File(generatedPath).copy(preferredOutputPath);
        }
        return preferredOutputPath;
      } catch (_) {
        return generatedPath;
      }
    } catch (e) {
      // 117 Session 1: do NOT swallow silently. A generation failure here is
      // indistinguishable in logs from "video has no thumbnail" unless we
      // emit telemetry. Callers still receive null (the benign "no thumbnail"
      // signal), but the failure is now observable.
      emitFlowEvent(
        layer: 'FL',
        event: 'VIDEO_THUMBNAIL_GENERATE_FAILED',
        details: {'path': videoPath, 'error': e.toString()},
      );
      return null;
    }
  }
}
