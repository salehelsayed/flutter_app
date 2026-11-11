import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../domain/custom_sticker.dart';
import '../domain/custom_sticker_asset.dart';

const _maxSide = 512;
const _maxPixels = _maxSide * _maxSide;
const _pngLimit = 2097152;
const _staticLimit = 262144;
const _animatedLimit = 524288;
const _maxFrames = 24;
const _maxDurationMs = 2000;

typedef _Size = ({int width, int height});
typedef _Frame = ({int width, int height, int durationMs});
typedef _WebP = ({int width, int height, List<_Frame> frames});
typedef _Chunk = ({String tag, int data, int size, int end});
typedef _Canonical = ({
  Uint8List bytes,
  int width,
  int height,
  int frameCount,
  int durationMs,
});

/// Validates a bounded snapshot and returns an independently owned temp file.
///
/// Producers retain ownership of [input] and its optional poster. This helper
/// does not authorize a source path or gate feature entrypoints; admission owns
/// those decisions. Codec work and synchronous file access run off the UI isolate.
Future<NormalizedStickerAsset> normalizeCustomStickerAsset(
  NormalizedStickerAsset input, {
  required Directory temporaryDirectory,
}) {
  final temporaryPath = temporaryDirectory.path;
  return Isolate.run(() => _normalize(input, temporaryPath));
}

NormalizedStickerAsset _normalize(
  NormalizedStickerAsset input,
  String temporaryPath,
) {
  final bytes = _snapshot(input);
  final _Canonical canonical;
  try {
    if (input.mime == 'image/png') {
      final size = _inspectPng(bytes);
      _matchClaims(input, size.width, size.height, 1, 0);
      final decoded = img.PngDecoder(maxPixels: _maxPixels).decode(bytes);
      if (decoded == null ||
          decoded.width != size.width ||
          decoded.height != size.height ||
          decoded.numFrames != 1 ||
          decoded.frameDuration != 0) {
        _invalid();
      }

      // Image.from/convert retain source metadata. Start from fresh pixels, and
      // erase original background RGB before either lossless or lossy encoding.
      final clean = img.Image(
        width: size.width,
        height: size.height,
        numChannels: 4,
      );
      for (final pixel in decoded) {
        final alpha = (pixel.aNormalized * 255).round();
        clean.setPixelRgba(
          pixel.x,
          pixel.y,
          alpha == 0 ? 0 : (pixel.rNormalized * 255).round(),
          alpha == 0 ? 0 : (pixel.gNormalized * 255).round(),
          alpha == 0 ? 0 : (pixel.bNormalized * 255).round(),
          alpha,
        );
      }
      var encoded = img.encodeWebP(clean, lossless: true, exact: true);
      // A finite ladder preserves dimensions and exact alpha. If even the last
      // candidate is too large, reject rather than publish an over-budget file.
      for (final quality in [90, 75, 60, 40]) {
        if (encoded.length <= _staticLimit) break;
        encoded = img.encodeWebP(
          clean,
          lossless: false,
          quality: quality,
          method: 4,
          alphaQuality: 100,
          exact: true,
        );
      }
      final structure = _inspectWebP(encoded);
      if (structure.frames.length != 1 ||
          structure.width != size.width ||
          structure.height != size.height) {
        _invalid();
      }
      _decodeWebP(encoded, structure);
      canonical = (
        bytes: encoded,
        width: size.width,
        height: size.height,
        frameCount: 1,
        durationMs: 0,
      );
    } else {
      final structure = _inspectWebP(bytes);
      final duration = _duration(structure);
      _matchClaims(
        input,
        structure.width,
        structure.height,
        structure.frames.length,
        duration,
      );
      _decodeWebP(bytes, structure);
      // Canonical producer WebP is validated, never re-encoded. In particular,
      // lossy reconstructed RGB under alpha zero is not a source-RGB oracle.
      canonical = (
        bytes: bytes,
        width: structure.width,
        height: structure.height,
        frameCount: structure.frames.length,
        durationMs: duration,
      );
    }
  } on CustomStickerException {
    rethrow;
  } catch (_) {
    // Codec failures describe an invalid input, not a successful partial image.
    _invalid();
  }
  return _publish(canonical, temporaryPath);
}

Uint8List _snapshot(NormalizedStickerAsset input) {
  _checkSize(input.width, input.height);
  if ((input.mime != 'image/png' && input.mime != 'image/webp') ||
      input.frameCount < 1 ||
      input.frameCount > _maxFrames ||
      input.durationMs < 0 ||
      input.durationMs > _maxDurationMs ||
      (input.frameCount == 1 && input.durationMs != 0) ||
      (input.frameCount > 1 && input.durationMs <= 0) ||
      (input.mime == 'image/png' && input.frameCount != 1) ||
      input.sha256Hex.length != 64 ||
      !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(input.sha256Hex)) {
    _invalid();
  }
  final limit = input.mime == 'image/png'
      ? _pngLimit
      : input.frameCount == 1
      ? _staticLimit
      : _animatedLimit;
  if (input.byteLength < 1 || input.byteLength > limit) _invalid();

  try {
    if (FileSystemEntity.typeSync(input.filePath, followLinks: false) !=
        FileSystemEntityType.file) {
      _invalid();
    }
    final handle = File(input.filePath).openSync(mode: FileMode.read);
    try {
      final size = handle.lengthSync();
      if (size != input.byteLength || size > limit) _invalid();
      final bytes = Uint8List(size);
      var offset = 0;
      while (offset < size) {
        final read = handle.readIntoSync(bytes, offset, size);
        if (read == 0) _invalid();
        offset += read;
      }
      // Read from the same handle throughout. Growth is detected without an
      // unbounded read; any same-size change must still match the claimed hash.
      if (handle.readByteSync() != -1 || handle.lengthSync() != size) {
        _invalid();
      }
      if (sha256.convert(bytes).toString() != input.sha256Hex.toLowerCase()) {
        _invalid();
      }
      return bytes;
    } finally {
      handle.closeSync();
    }
  } on FileSystemException {
    _invalid();
  }
}

_Size _inspectPng(Uint8List bytes) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length > _pngLimit || bytes.length < 33) _invalid();
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) _invalid();
  }
  final data = ByteData.sublistView(bytes);
  var offset = 8;
  _Size? size;
  var colorType = -1;
  var paletteEntries = 0;
  var hasTransparency = false;
  var hasData = false;
  var dataEnded = false;
  var dataLength = 0;
  while (offset < bytes.length) {
    if (bytes.length - offset < 12) _invalid();
    final length = data.getUint32(offset, Endian.big);
    if (length > bytes.length - offset - 12) _invalid();
    final start = offset + 8;
    final end = start + length;
    final tag = String.fromCharCodes(bytes, offset + 4, start);
    for (var i = offset + 4; i < start; i++) {
      final code = bytes[i];
      if (!(code >= 65 && code <= 90) && !(code >= 97 && code <= 122)) {
        _invalid();
      }
    }
    if ((bytes[offset + 6] & 32) != 0 ||
        _crc32(bytes, offset + 4, end) != data.getUint32(end, Endian.big)) {
      _invalid();
    }
    if (size == null && tag != 'IHDR') _invalid();
    if (hasData && tag != 'IDAT') dataEnded = true;
    switch (tag) {
      case 'IHDR':
        if (size != null || length != 13) _invalid();
        final width = data.getUint32(start, Endian.big);
        final height = data.getUint32(start + 4, Endian.big);
        _checkSize(width, height);
        size = (width: width, height: height);
        colorType = bytes[start + 9];
        if (bytes[start + 10] != 0 ||
            bytes[start + 11] != 0 ||
            bytes[start + 12] > 1) {
          _invalid();
        }
      case 'PLTE':
        if (hasData ||
            paletteEntries != 0 ||
            length < 3 ||
            length > 768 ||
            length % 3 != 0) {
          _invalid();
        }
        paletteEntries = length ~/ 3;
      case 'tRNS':
        if (hasData ||
            hasTransparency ||
            !(colorType == 0 && length == 2 ||
                colorType == 2 && length == 6 ||
                colorType == 3 && length > 0 && length <= paletteEntries)) {
          _invalid();
        }
        hasTransparency = true;
      case 'IDAT':
        if (dataEnded || (colorType == 3 && paletteEntries == 0)) _invalid();
        hasData = true;
        dataLength += length;
      case 'IEND':
        if (length != 0 ||
            !hasData ||
            dataLength == 0 ||
            end + 4 != bytes.length) {
          _invalid();
        }
        return size!;
      case 'eXIf':
      case 'iCCP':
      case 'acTL':
      case 'fcTL':
      case 'fdAT':
        _invalid();
      default:
        // Unrecognized critical data cannot be safely interpreted. Ancillary
        // text is bounded by the source cap and dropped by the fresh RGBA image.
        if ((bytes[offset + 4] & 32) == 0) _invalid();
    }
    offset = end + 4;
  }
  _invalid();
}

_WebP _inspectWebP(Uint8List bytes) {
  if (bytes.length < 20 ||
      bytes.length > _animatedLimit ||
      String.fromCharCodes(bytes, 0, 4) != 'RIFF' ||
      String.fromCharCodes(bytes, 8, 12) != 'WEBP' ||
      ByteData.sublistView(bytes).getUint32(4, Endian.little) !=
          bytes.length - 8) {
    _invalid();
  }
  final chunks = _chunks(bytes, 12, bytes.length);
  if (chunks.isEmpty) _invalid();
  _Size? canvas;
  var animated = false;
  var index = 0;
  if (chunks.first.tag == 'VP8X') {
    final chunk = chunks.first;
    if (chunk.size != 10 ||
        (bytes[chunk.data] & ~0x12) != 0 ||
        _u24(bytes, chunk.data + 1) != 0) {
      _invalid();
    }
    final width = _u24(bytes, chunk.data + 4) + 1;
    final height = _u24(bytes, chunk.data + 7) + 1;
    _checkSize(width, height);
    canvas = (width: width, height: height);
    animated = (bytes[chunk.data] & 2) != 0;
    index = 1;
  }
  final frames = <_Frame>[];
  if (animated) {
    if (index >= chunks.length ||
        chunks[index].tag != 'ANIM' ||
        chunks[index].size != 6) {
      _invalid();
    }
    index++;
    var duration = 0;
    for (; index < chunks.length; index++) {
      final chunk = chunks[index];
      if (chunk.tag != 'ANMF' ||
          chunk.size < 16 ||
          frames.length >= _maxFrames) {
        _invalid();
      }
      final start = chunk.data;
      final x = _u24(bytes, start) * 2;
      final y = _u24(bytes, start + 3) * 2;
      final width = _u24(bytes, start + 6) + 1;
      final height = _u24(bytes, start + 9) + 1;
      final durationMs = _u24(bytes, start + 12);
      _checkSize(width, height);
      if ((bytes[start + 15] & ~3) != 0 ||
          x + width > canvas!.width ||
          y + height > canvas.height) {
        _invalid();
      }
      duration += durationMs;
      if (duration > _maxDurationMs) _invalid();
      final inner = _imageSize(bytes, _chunks(bytes, start + 16, chunk.end));
      if (inner.width != width || inner.height != height) _invalid();
      frames.add((width: width, height: height, durationMs: durationMs));
    }
    if (frames.isEmpty ||
        (frames.length == 1 && duration != 0) ||
        (frames.length > 1 && duration <= 0)) {
      _invalid();
    }
  } else {
    final image = _imageSize(bytes, chunks.sublist(index));
    if (canvas != null && canvas != image) _invalid();
    if (canvas == null && chunks.length != 1) _invalid();
    canvas ??= image;
    frames.add((width: image.width, height: image.height, durationMs: 0));
  }
  if (bytes.length > (frames.length == 1 ? _staticLimit : _animatedLimit)) {
    _invalid();
  }
  return (width: canvas!.width, height: canvas.height, frames: frames);
}

List<_Chunk> _chunks(Uint8List bytes, int start, int end) {
  final data = ByteData.sublistView(bytes);
  final result = <_Chunk>[];
  var offset = start;
  while (offset < end) {
    if (end - offset < 8) _invalid();
    final size = data.getUint32(offset + 4, Endian.little);
    if (size > end - offset - 8) _invalid();
    final payload = offset + 8;
    final payloadEnd = payload + size;
    final next = payloadEnd + (size & 1);
    if (next > end || (size.isOdd && bytes[payloadEnd] != 0)) _invalid();
    result.add((
      tag: String.fromCharCodes(bytes, offset, payload - 4),
      data: payload,
      size: size,
      end: payloadEnd,
    ));
    offset = next;
  }
  return result;
}

_Size _imageSize(Uint8List bytes, List<_Chunk> chunks) {
  if (chunks.isEmpty || chunks.length > 2) _invalid();
  final image = chunks.last;
  final hasAlpha = chunks.length == 2;
  if (hasAlpha && (chunks.first.tag != 'ALPH' || image.tag != 'VP8 ')) {
    _invalid();
  }
  final data = ByteData.sublistView(bytes);
  final start = image.data;
  final int width;
  final int height;
  if (image.tag == 'VP8L') {
    if (image.size < 5 || bytes[start] != 0x2f) _invalid();
    final packed = data.getUint32(start + 1, Endian.little);
    if ((packed >>> 29) != 0) _invalid();
    width = (packed & 0x3fff) + 1;
    height = ((packed >>> 14) & 0x3fff) + 1;
  } else if (image.tag == 'VP8 ') {
    if (image.size < 10) _invalid();
    final tag = _u24(bytes, start);
    if ((tag & 1) != 0 ||
        ((tag >>> 1) & 7) > 3 ||
        (tag & 16) == 0 ||
        (tag >>> 5) < 1 ||
        (tag >>> 5) > image.size - 10 ||
        bytes[start + 3] != 0x9d ||
        bytes[start + 4] != 0x01 ||
        bytes[start + 5] != 0x2a) {
      _invalid();
    }
    // image4.12's decoder uses these full words for allocation. Reject scaling
    // bits as well as large dimensions rather than masking a dangerous value.
    width = data.getUint16(start + 6, Endian.little);
    height = data.getUint16(start + 8, Endian.little);
  } else {
    _invalid();
  }
  _checkSize(width, height);
  if (hasAlpha) {
    final alpha = chunks.first;
    if (alpha.size < 1) _invalid();
    final flags = bytes[alpha.data];
    final compression = flags & 3;
    if ((flags & 0xc0) != 0 ||
        compression > 1 ||
        ((flags >>> 4) & 3) > 1 ||
        (compression == 0 && alpha.size != 1 + width * height) ||
        (compression == 1 && alpha.size < 2)) {
      _invalid();
    }
  }
  return (width: width, height: height);
}

void _decodeWebP(Uint8List bytes, _WebP structure) {
  // The codec counts composited canvas pixels across the entire animation.
  // Per-axis, inner-raster and frame-count limits have already been checked.
  final decoder = img.WebPDecoder()
    ..maxPixels = _maxPixels * structure.frames.length;
  final decoded = decoder.decode(bytes);
  if (decoded == null ||
      decoded.width != structure.width ||
      decoded.height != structure.height ||
      decoded.numFrames != structure.frames.length) {
    _invalid();
  }
  // The decoder can skip a failed frame: exact count and each duration must
  // agree, so a partial decode is never accepted as the original animation.
  for (var i = 0; i < structure.frames.length; i++) {
    final frame = decoded.frames[i];
    if (frame.width != structure.width ||
        frame.height != structure.height ||
        frame.frameDuration != structure.frames[i].durationMs) {
      _invalid();
    }
  }
}

NormalizedStickerAsset _publish(_Canonical canonical, String temporaryPath) {
  final digest = sha256.convert(canonical.bytes).toString();
  File? owned;
  var published = false;
  try {
    if (FileSystemEntity.typeSync(temporaryPath, followLinks: false) !=
        FileSystemEntityType.directory) {
      _storageFailure();
    }
    final random = Random.secure();
    for (var attempt = 0; attempt < 4; attempt++) {
      final nonce = List<int>.generate(
        16,
        (_) => random.nextInt(256),
      ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
      final candidate = File(p.join(temporaryPath, 'sticker-$nonce.webp'));
      try {
        candidate.createSync(exclusive: true);
        owned = candidate;
        break;
      } on PathExistsException {
        // An exclusive-create collision never grants ownership of that path.
      }
    }
    if (owned == null) _storageFailure();
    owned.writeAsBytesSync(canonical.bytes, flush: true);
    final result = NormalizedStickerAsset(
      filePath: owned.path,
      sha256Hex: digest,
      mime: 'image/webp',
      byteLength: canonical.bytes.length,
      width: canonical.width,
      height: canonical.height,
      frameCount: canonical.frameCount,
      durationMs: canonical.durationMs,
    );
    published = true;
    return result;
  } on FileSystemException {
    _storageFailure();
  } finally {
    if (!published && owned != null) {
      // Only the exact exclusively created file is ours; no directory sweeps.
      try {
        owned.deleteSync();
      } on FileSystemException {
        _storageFailure();
      }
    }
  }
}

void _matchClaims(
  NormalizedStickerAsset input,
  int width,
  int height,
  int frameCount,
  int durationMs,
) {
  if (input.width != width ||
      input.height != height ||
      input.frameCount != frameCount ||
      input.durationMs != durationMs) {
    _invalid();
  }
}

void _checkSize(int width, int height) {
  if (width < 1 || width > _maxSide || height < 1 || height > _maxSide) {
    _invalid();
  }
}

int _duration(_WebP structure) =>
    structure.frames.fold<int>(0, (total, frame) => total + frame.durationMs);

int _u24(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);

final _crcTable = List<int>.generate(256, (value) {
  var crc = value;
  for (var bit = 0; bit < 8; bit++) {
    crc = (crc & 1) == 0 ? crc >>> 1 : (crc >>> 1) ^ 0xedb88320;
  }
  return crc;
});

int _crc32(Uint8List bytes, int start, int end) {
  var crc = 0xffffffff;
  for (var i = start; i < end; i++) {
    crc = (crc >>> 8) ^ _crcTable[(crc ^ bytes[i]) & 255];
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

Never _invalid() =>
    throw const CustomStickerException(CustomStickerErrorCode.invalidAsset);

Never _storageFailure() =>
    throw const CustomStickerException(CustomStickerErrorCode.storageFailure);
