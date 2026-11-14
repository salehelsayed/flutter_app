import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, PlatformException;
import 'package:flutter_app/core/config/custom_stickers_flag.dart';
import 'package:flutter_app/features/stickers/application/sticker_cutout.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

const _maximumSide = 2048;
const _maximumPngBytes = 24 * 1024 * 1024;

/// Owns each pending job until a validated PNG is returned to its caller.
final class MethodChannelStickerCutoutService implements StickerCutoutService {
  MethodChannelStickerCutoutService({
    required Directory temporaryDirectory,
    MethodChannel? channel,
    bool enabled = kCustomStickersEnabled,
  }) : _temporaryDirectory = temporaryDirectory,
       _channel =
           channel ?? const MethodChannel('mknoon/custom_sticker_cutout'),
       _enabled = enabled;

  final Directory _temporaryDirectory;
  final MethodChannel _channel;
  final bool _enabled;
  _CutoutJob? _job;

  @override
  Future<StickerCutoutAvailability> availability() async {
    if (!_enabled) return StickerCutoutAvailability.unsupported;
    try {
      return switch (await _channel.invokeMethod<Object?>('availability')) {
        'ready' => StickerCutoutAvailability.ready,
        'needsModel' => StickerCutoutAvailability.needsModel,
        _ => StickerCutoutAvailability.unsupported,
      };
    } on MissingPluginException {
      return StickerCutoutAvailability.unsupported;
    } catch (error) {
      throw _safeError(error);
    }
  }

  @override
  Future<StickerCutout?> extract(String sourceImagePath) {
    if (!_enabled) {
      return Future.error(
        const StickerCutoutException(StickerCutoutErrorCode.disabled),
      );
    }
    if (_job != null) {
      return Future.error(
        const StickerCutoutException(StickerCutoutErrorCode.unavailable),
      );
    }
    final job = _CutoutJob();
    _job = job;
    unawaited(_extract(job, sourceImagePath));
    return job.result.future;
  }

  @override
  Future<void> cancel() {
    if (!_enabled) return Future.value();
    final job = _job;
    if (job == null) return Future.value();
    final cancellation = job.cancellation;
    if (cancellation != null) return cancellation;
    job.cancelled = true;
    return job.cancellation = _cancel(job);
  }

  Future<void> _cancel(_CutoutJob job) async {
    try {
      if (job.nativePending) {
        await _channel.invokeMethod<void>('cancel', {'jobId': job.id});
      }
    } catch (_) {
      // A detached or failing native plugin must not turn Cancel into a UI error.
    } finally {
      await _deletePending(job);
      _release(job);
      if (!job.result.isCompleted) job.result.complete(null);
    }
  }

  Future<void> _extract(_CutoutJob job, String sourcePath) async {
    StickerCutout? value;
    StickerCutoutException? failure;
    try {
      await _validateSource(sourcePath);
      if (job.cancelled) return;
      final random = Random.secure();
      final token = List.generate(
        16,
        (_) => random.nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      final created = await _temporaryDirectory.createTemp(
        'mknoon-sticker-cutout-$token-',
      );
      job.directory = created;
      if (job.cancelled) return;
      final directory = Directory(await created.resolveSymbolicLinks());
      job.directory = directory;
      job.id = p.basename(directory.path);
      if (job.cancelled) return;
      final output = File(p.join(directory.path, 'result.png'));

      Object? native;
      job.nativePending = true;
      try {
        native = await _channel.invokeMethod<Object?>('extract', {
          'jobId': job.id,
          'sourceImagePath': sourcePath,
          'outputPath': output.path,
        });
      } finally {
        job.nativePending = false;
      }
      if (job.cancelled || native == null) return;
      final description = _description(native);
      final bytes = await _validatedSnapshot(
        output.path,
        description.width,
        description.height,
      );
      if (job.cancelled) return;
      if (bytes == null || !await _isOwnedDirectory(directory)) _failed();
      if (job.cancelled) return;

      // Publish the bytes actually validated, rather than reopening a mutable
      // native output for the caller. Rename replaces only our own path/link.
      final publication = await directory.createTemp('.validated-');
      if (job.cancelled) return;
      final staged = File(p.join(publication.path, 'result.png'));
      await staged.writeAsBytes(bytes, flush: true);
      if (job.cancelled) return;
      if (!await _isOwnedDirectory(directory)) _failed();
      if (job.cancelled) return;
      await staged.rename(output.path);
      if (job.cancelled) return;
      await publication.delete();
      if (job.cancelled) return;
      value = StickerCutout(
        imagePath: output.path,
        width: description.width,
        height: description.height,
        subjectBounds: description.bounds,
      );
    } catch (error) {
      failure = _safeError(error);
    } finally {
      if (value == null || job.cancelled) await _deletePending(job);
      if (!job.cancelled) {
        job.published = value != null;
        _release(job);
        if (!job.result.isCompleted) {
          if (failure != null) {
            job.result.completeError(failure);
          } else {
            job.result.complete(value);
          }
        }
      }
    }
  }

  void _release(_CutoutJob job) {
    // A cancelled native reply can arrive while a successor is active.
    if (identical(_job, job)) _job = null;
  }
}

final class _CutoutJob {
  final result = Completer<StickerCutout?>();
  Directory? directory;
  String? id;
  bool nativePending = false;
  bool cancelled = false;
  bool published = false;
  Future<void>? cancellation;
}

Future<void> _validateSource(String path) async {
  try {
    if (!p.isAbsolute(path)) throw const FormatException();
    final stat = await File(path).stat();
    if (stat.type != FileSystemEntityType.file || stat.size == 0) {
      throw const FormatException();
    }
  } catch (_) {
    throw const StickerCutoutException(StickerCutoutErrorCode.invalidSource);
  }
}

Future<bool> _isOwnedDirectory(Directory directory) async =>
    await FileSystemEntity.type(directory.path, followLinks: false) ==
        FileSystemEntityType.directory &&
    await directory.resolveSymbolicLinks() == directory.path;

Future<void> _deletePending(_CutoutJob job) async {
  final directory = job.directory;
  if (directory == null || job.published) return;
  try {
    // This is only the directory returned by createTemp, never native metadata.
    // Recursive deletion unlinks symlinks without following their targets.
    await directory.delete(recursive: true);
  } on FileSystemException {
    // Cancellation and the delayed native reply can race to remove this job.
    // The delayed reply retries cleanup, including any late native write.
  }
}

({int width, int height, Rect bounds}) _description(Object native) {
  if (native is! Map) _failed();
  final width = native['width'];
  final height = native['height'];
  final bounds = native['subjectBounds'];
  if (width is! int ||
      height is! int ||
      width < 1 ||
      width > _maximumSide ||
      height < 1 ||
      height > _maximumSide ||
      bounds is! Map) {
    _failed();
  }
  double coordinate(String name) {
    final value = bounds[name];
    if (value is! num || !value.isFinite || value < 0 || value > 1) _failed();
    return value.toDouble();
  }

  final rectangle = Rect.fromLTRB(
    coordinate('left'),
    coordinate('top'),
    coordinate('right'),
    coordinate('bottom'),
  );
  if (rectangle.isEmpty) _failed();
  return (width: width, height: height, bounds: rectangle);
}

StickerCutoutException _safeError(Object error) {
  if (error is StickerCutoutException) return error;
  if (error is MissingPluginException) {
    return const StickerCutoutException(StickerCutoutErrorCode.unsupported);
  }
  final code = error is PlatformException
      ? switch (error.code) {
          'unsupported' => StickerCutoutErrorCode.unsupported,
          'unavailable' => StickerCutoutErrorCode.unavailable,
          'invalidSource' ||
          'invalid_source' => StickerCutoutErrorCode.invalidSource,
          _ => StickerCutoutErrorCode.failed,
        }
      : StickerCutoutErrorCode.failed;
  return StickerCutoutException(code);
}

Never _failed() =>
    throw const StickerCutoutException(StickerCutoutErrorCode.failed);

// Keep the isolate closure outside the service/job scope: it captures only
// sendable path/dimension values, not a messenger, completer, or UI owner.
Future<Uint8List?> _validatedSnapshot(String path, int width, int height) =>
    Isolate.run(() => _readAndValidate(path, width, height));

Uint8List? _readAndValidate(String path, int width, int height) {
  try {
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.file ||
        File(path).resolveSymbolicLinksSync() != path) {
      return null;
    }
    final handle = File(path).openSync(mode: FileMode.read);
    late Uint8List bytes;
    try {
      final size = handle.lengthSync();
      if (size < 45 || size > _maximumPngBytes) return null;
      bytes = Uint8List(size);
      var offset = 0;
      while (offset < size) {
        final count = handle.readIntoSync(bytes, offset, size);
        if (count == 0) return null;
        offset += count;
      }
      if (handle.readByteSync() != -1 || handle.lengthSync() != size) {
        return null;
      }
    } finally {
      handle.closeSync();
    }
    if (!_validPng(bytes, width, height)) return null;
    final image = img.PngDecoder(
      maxPixels: _maximumSide * _maximumSide,
    ).decode(bytes);
    if (image == null ||
        image.width != width ||
        image.height != height ||
        image.numFrames != 1 ||
        !image.hasAlpha ||
        !image.exif.isEmpty ||
        image.iccProfile != null ||
        (image.textData?.isNotEmpty ?? false)) {
      return null;
    }
    for (final pixel in image) {
      if (pixel.a == 0 && (pixel.r != 0 || pixel.g != 0 || pixel.b != 0)) {
        return null;
      }
    }
    return bytes;
  } catch (_) {
    // Decoder and filesystem diagnostics can contain paths or native payloads.
    return null;
  }
}

bool _validPng(Uint8List bytes, int width, int height) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return false;
  }
  final data = ByteData.sublistView(bytes);
  var offset = 8;
  var header = false;
  var colorType = -1;
  var bits = 0;
  var paletteEntries = 0;
  var transparency = false;
  var hasData = false;
  var dataEnded = false;
  var dataLength = 0;
  while (offset < bytes.length) {
    if (bytes.length - offset < 12) return false;
    final length = data.getUint32(offset, Endian.big);
    if (length > bytes.length - offset - 12) return false;
    final start = offset + 8;
    final end = start + length;
    final tag = String.fromCharCodes(bytes, offset + 4, start);
    if (_crc32(bytes, offset + 4, end) != data.getUint32(end, Endian.big)) {
      return false;
    }
    if (!header && tag != 'IHDR') return false;
    if (hasData && tag != 'IDAT') dataEnded = true;
    switch (tag) {
      case 'IHDR':
        if (header ||
            length != 13 ||
            data.getUint32(start, Endian.big) != width ||
            data.getUint32(start + 4, Endian.big) != height) {
          return false;
        }
        header = true;
        bits = bytes[start + 8];
        colorType = bytes[start + 9];
        final validBits = switch (colorType) {
          0 => const [1, 2, 4, 8, 16].contains(bits),
          2 || 4 || 6 => bits == 8 || bits == 16,
          3 => const [1, 2, 4, 8].contains(bits),
          _ => false,
        };
        if (!validBits ||
            bytes[start + 10] != 0 ||
            bytes[start + 11] != 0 ||
            bytes[start + 12] > 1) {
          return false;
        }
      case 'PLTE':
        if (colorType != 3 ||
            hasData ||
            paletteEntries != 0 ||
            length < 3 ||
            length > 768 ||
            length % 3 != 0) {
          return false;
        }
        paletteEntries = length ~/ 3;
        if (paletteEntries > (1 << bits)) return false;
      case 'tRNS':
        if (hasData ||
            transparency ||
            !(colorType == 0 && length == 2 ||
                colorType == 2 && length == 6 ||
                colorType == 3 && length > 0 && length <= paletteEntries)) {
          return false;
        }
        transparency = true;
      case 'IDAT':
        if (dataEnded || (colorType == 3 && paletteEntries == 0)) return false;
        hasData = true;
        dataLength += length;
      case 'IEND':
        return length == 0 &&
            hasData &&
            dataLength > 0 &&
            end + 4 == bytes.length;
      default:
        // Only raster structure and required palette/transparency data pass.
        // This excludes APNG, EXIF, ICC, text and unknown private ancillary data.
        return false;
    }
    offset = end + 4;
  }
  return false;
}

int _crc32(Uint8List bytes, int start, int end) {
  var crc = 0xffffffff;
  for (var i = start; i < end; i++) {
    crc ^= bytes[i];
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 0 ? crc >>> 1 : (crc >>> 1) ^ 0xedb88320;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
